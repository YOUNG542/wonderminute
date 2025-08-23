import Foundation
import FirebaseAuth
import FirebaseFirestore

struct PeerProfile: Identifiable {
    let id: String          // uid
    let nickname: String
    let photoURL: String?
    let gender: String?
    let mbti: String?
    let interests: [String]?
}

final class MatchWatcher: ObservableObject {
    private let db = Firestore.firestore()
    private let call: CallEngine
    private var started = false

    private var meListener: ListenerRegistration?
    private var roomListener: ListenerRegistration?
    private var peerListener: ListenerRegistration?

    // Token 캐시(만료 임박시에만 재발급)
    private let tokenCache = TokenCache(fetcher: fetchJoinFromFunctions)

    @Published var peer: PeerProfile?

    init(call: CallEngine) { self.call = call }

    deinit {
        meListener?.remove(); roomListener?.remove(); peerListener?.remove()
        print("🔎[MatchWatcher] deinit – listeners removed")
    }

    func start() {
        guard !started else { print("🔎[MatchWatcher] start() ignored – already started"); return }
        started = true
        guard let user = Auth.auth().currentUser else { print("❌[MatchWatcher] start(): no currentUser"); return }
        let uid = user.uid
        print("🔎[MatchWatcher] start() for uid=\(uid)")

        meListener = db.collection("users").document(uid).addSnapshotListener { [weak self] snap, err in
            guard let self else { return }
            if let err = err { print("❌[MatchWatcher] user doc listen error: \(err)"); return }
            guard let snap else { print("❌[MatchWatcher] user doc snapshot nil"); return }

            let roomId = (snap.get("activeRoomId") as? String) ?? ""
            print("🔎[MatchWatcher] users/\(uid) activeRoomId='\(roomId)' exists=\(snap.exists)")
            if roomId.isEmpty {
                self.call.leaveIfJoined()
                self.roomListener?.remove(); self.roomListener = nil
                self.peerListener?.remove(); self.peerListener = nil
                self.peer = nil
                return
            }

            

            self.watchRoom(roomId: roomId)
        }
    }
    func stop() {
        meListener?.remove();   meListener = nil
        roomListener?.remove(); roomListener = nil
        peerListener?.remove(); peerListener = nil
        started = false
    }

    private func watchRoom(roomId: String) {
        guard roomListener == nil else { return } // 1회만
        print("🔎[MatchWatcher] watchRoomDocument \(roomId)")
        roomListener = db.collection("matchedRooms").document(roomId)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err = err { print("❌[MatchWatcher] room listen error: \(err)"); return }
                guard let snap = snap else { print("❌[MatchWatcher] room snap nil"); return }

                if !snap.exists {
                    print("🔎[MatchWatcher] room deleted -> leave() & clear peer")
                    DispatchQueue.main.async { self.call.remoteEnded = true }
                    self.call.leaveIfJoined()
                    self.roomListener?.remove(); self.roomListener = nil
                    self.peerListener?.remove(); self.peerListener = nil
                    self.peer = nil
                    return
                }

                // 상대 프로필 구독
                if let users = snap.get("users") as? [String],
                   let myUid = Auth.auth().currentUser?.uid,
                   let peerUid = users.first(where: { $0 != myUid }) {
                    self.listenPeerProfile(uid: peerUid)
                }

                let status = (snap.get("status") as? String) ?? ""
                print("🔎[MatchWatcher] room status='\(status)'")

                switch status {
                case "ended":
                    DispatchQueue.main.async { self.call.remoteEnded = true }
                    self.call.leaveIfJoined()

                case "active":
                    // ✅ 이때만 join
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            try await self.call.joinIfNeeded {
                                try await self.tokenCache.validOrFetch(roomId: roomId, minRemain: 180)
                            }
                        } catch {
                            print("❌[MatchWatcher] joinIfNeeded error: \(error)")
                        }
                    }

                default:
                    // "pending"/"matched" 등: 대기 (조기 join 방지)
                    self.call.leaveIfJoined()
                }

            }
    }

    private func listenPeerProfile(uid: String) {
        if peer?.id == uid, peerListener != nil { return } // 이미 리슨 중이면 스킵
        peerListener?.remove()

        peerListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let d = snap?.data() else { return }
                let p = PeerProfile(
                    id: uid,
                    nickname: (d["nickname"] as? String) ?? "상대방",
                    photoURL: d["photoURL"] as? String,
                    gender: d["gender"] as? String,
                    mbti: d["mbti"] as? String,
                    interests: d["interests"] as? [String]
                )
                DispatchQueue.main.async { self.peer = p }
            }
    }
}

// MARK: - TokenCache with external fetcher
final class TokenCache {
    private var current: AgoraJoin?
    private let fetcher: (_ roomId: String) async throws -> AgoraJoin

    init(fetcher: @escaping (_ roomId: String) async throws -> AgoraJoin) {
        self.fetcher = fetcher
    }

    func validOrFetch(roomId: String, minRemain: TimeInterval) async throws -> AgoraJoin {
        if let c = current, c.expireAt.timeIntervalSinceNow > minRemain, c.channel == roomId {
            return c
        }
        let fresh = try await fetcher(roomId)
        current = fresh
        return fresh
    }
}

// 실제 토큰/조인 정보 가져오기 (Functions.getAgoraToken 이용)
private func fetchJoinFromFunctions(roomId: String) async throws -> AgoraJoin {
    // FirebaseAuth ID token → Functions HTTP(POST) 호출
    let user = Auth.auth().currentUser
    guard let idToken = try await user?.getIDToken() else {
        throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No ID token"])
    }

    // rtcUid: uid 해시
    let myUid = user?.uid ?? ""
    let rtc = UInt(bitPattern: myUid.hashValue) % 2_000_000_000

    var req = URLRequest(url: FunctionsAPI.getAgoraTokenURL)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["roomId": roomId, "rtcUid": rtc])

    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse { print("🔎[TokenCache] getAgoraToken status=\(http.statusCode)") }
    struct R: Decodable { let token: String; let appId: String; let channel: String; let rtcUid: UInt; let expireSeconds: Int }
    let r = try JSONDecoder().decode(R.self, from: data)
    let expireAt = Date().addingTimeInterval(TimeInterval(r.expireSeconds))
    return AgoraJoin(appId: r.appId, channel: r.channel, token: r.token, rtcUid: r.rtcUid, expireAt: expireAt)
}
