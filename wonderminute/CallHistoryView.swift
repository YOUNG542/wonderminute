import SwiftUI
import FirebaseAuth
import FirebaseFirestore


// MARK: - Models (수동 파싱 버전)

struct CallSession: Identifiable {
    let id: String
    let users: [String]
    let startedAt: Date
    let endedAt: Date?
    let status: String?

    init?(doc: DocumentSnapshot) {
        guard let data = doc.data(),
              let users = data["users"] as? [String],
              let startedTs = data["startedAt"] as? Timestamp
        else { return nil }

        self.id = doc.documentID
        self.users = users
        self.startedAt = startedTs.dateValue()
        self.endedAt = (data["endedAt"] as? Timestamp)?.dateValue()
        self.status = data["status"] as? String
    }
}

struct UserProfile: Identifiable {
    let id: String
    let nickname: String
    let photoURL: String?

    init?(doc: QueryDocumentSnapshot) {
        let data = doc.data()
        // 필드명: nickname / ProfileImageUrl
        guard let nickname = data["nickname"] as? String else { return nil }
        self.id = doc.documentID
        self.nickname = nickname
        self.photoURL = data["ProfileImageUrl"] as? String
    }
}

// UI에 뿌릴 Row 데이터
struct CallHistoryRow: Identifiable {
    var id: String            // sessionId
    var otherUid: String
    var otherNickname: String
    var otherPhotoURL: String?
    var startedAt: Date
    var durationSec: Int?
    var status: String?
}

// MARK: - ViewModel

final class CallHistoryViewModel: ObservableObject {
    @Published var rows: [CallHistoryRow] = []
    @Published var loading = false
    @Published var error: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    deinit { listener?.remove() }

    func load() {
        guard let myUid = Auth.auth().currentUser?.uid, !myUid.isEmpty else {
            self.error = "로그인이 필요합니다."
            return
        }

        loading = true
        error = nil
        listener?.remove()

        listener = db.collection("callSessions")
            .whereField("users", arrayContains: myUid)
            .order(by: "startedAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snap, err in
                guard let self = self else { return }
                if let err = err {
                    self.error = err.localizedDescription
                    self.loading = false
                    return
                }
                let sessions: [CallSession] = snap?.documents.compactMap { CallSession(doc: $0) } ?? []

                // 상대 UID만 추출
                let otherUids: [String] = sessions.compactMap { s in
                    s.users.first(where: { $0 != myUid })
                }

                // 프로필 일괄 조회 후 Row 매핑
                self.fetchProfiles(uids: otherUids) { profiles in
                    let rows: [CallHistoryRow] = sessions.compactMap { s in
                        let other = s.users.first(where: { $0 != myUid }) ?? ""
                        let p = profiles[other]
                        let duration = Self.durationSec(start: s.startedAt, end: s.endedAt)
                        return CallHistoryRow(
                            id: s.id,
                            otherUid: other,
                            otherNickname: p?.nickname ?? "(알 수 없음)",
                            otherPhotoURL: p?.photoURL,
                            startedAt: s.startedAt,
                            durationSec: duration,
                            status: s.status
                        )
                    }
                    self.rows = rows
                    self.loading = false
                }
            }
    }

    private static func durationSec(start: Date, end: Date?) -> Int? {
        guard let end = end else { return nil }
        return max(0, Int(end.timeIntervalSince(start)))
    }

    // users/{uid} 문서를 10개씩 chunk로 IN 쿼리
    private func fetchProfiles(uids: [String], completion: @escaping ([String: UserProfile]) -> Void) {
        let uniq = Array(Set(uids))
        guard !uniq.isEmpty else { completion([:]); return }

        var result: [String: UserProfile] = [:]
        let chunks = uniq.chunked(into: 10) // Firestore 'in' 최대 10개
        let group = DispatchGroup()

        for c in chunks {
            group.enter()
            db.collection("users")
                .whereField(FieldPath.documentID(), in: c)
                .getDocuments { snap, err in
                    defer { group.leave() }
                    guard err == nil, let docs = snap?.documents else { return }
                    for d in docs {
                        if let p = UserProfile(doc: d) {
                            result[p.id] = p
                        }
                    }
                }
        }

        group.notify(queue: .main) { completion(result) }
    }
}

// MARK: - View

struct CallHistoryView: View {
    @StateObject private var vm = CallHistoryViewModel()

    // ↓ 추가: 채팅방 진입 제어용 상태
    @State private var pushChat = false
    @State private var activeRoomId: String?
    @State private var activeOtherNickname: String = ""
    @State private var activeOtherPhotoURL: String?
    @State private var activeOtherUid: String = ""
    
    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()

            List {
                         
                NavigationLink(isActive: $pushChat) {
                    Group {
                        if let rid = activeRoomId, !rid.isEmpty {
                            ChatRoomView(roomId: rid,
                                         otherNickname: activeOtherNickname,
                                         otherPhotoURL: activeOtherPhotoURL,
                                         otherUid: activeOtherUid)
                        } else {
                            EmptyView()
                        }
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
                .frame(width: 0, height: 0)



                if vm.loading {
                    HStack {
                        Spacer()
                        ProgressView("불러오는 중…")
                        Spacer()
                    }
                }

                if let err = vm.error {
                    Text(err).foregroundStyle(.red)
                }

                Section(header: Text("최근 통화").font(.headline)) {
                    if vm.rows.isEmpty && !vm.loading && vm.error == nil {
                        Text("통화 기록이 없습니다.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(vm.rows) { row in
                        HStack(spacing: 12) {
                            Avatar(urlString: row.otherPhotoURL, fallback: row.otherNickname)
                                .frame(width: 42, height: 42)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.otherNickname)
                                    .font(.subheadline).bold()

                                Text("\(row.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(formattedDuration(row.durationSec))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                            // "채팅하기" 버튼
                            Button {
                                // 이전 상태 초기화
                                pushChat = false
                                activeRoomId = nil

                                activeOtherNickname = row.otherNickname
                                activeOtherPhotoURL = row.otherPhotoURL
                                activeOtherUid = row.otherUid                    // ✅ 추가

                                ChatService.shared.getOrCreateRoom(with: row.otherUid) { roomId, err in
                                    guard err == nil, let rid = roomId, !rid.isEmpty else { return }
                                    DispatchQueue.main.async {
                                        activeRoomId = rid
                                        pushChat = true
                                    }
                                }

                            } label: {
                                Text("채팅하기")
                                    .font(.caption.weight(.semibold))
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)




                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("통화 내역")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { vm.load() }
            .onAppear { vm.load() }
           
        }
    }

    private func formattedDuration(_ sec: Int?) -> String {
        guard let sec = sec else { return "진행 중" }
        let m = sec / 60
        let s = sec % 60
        return String(format: "%d분 %02d초", m, s)
    }
}

// MARK: - Avatar View

struct Avatar: View {
    let urlString: String?
    let fallback: String

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack { Circle().fill(.thinMaterial); ProgressView().scaleEffect(0.8) }
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Placeholder()
                    @unknown default:
                        Placeholder()
                    }
                }
            } else {
                Placeholder()
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 1))
        .shadow(radius: 1)
    }

    @ViewBuilder
    private func Placeholder() -> some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Text(initials(from: fallback))
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
    }

    private func initials(from name: String) -> String {
        let comps = name.split(separator: " ")
        if comps.count >= 2 {
            return String(comps[0].prefix(1) + comps[1].prefix(1))
        }
        return String(name.prefix(2))
    }
}

// MARK: - Helpers

extension Array where Element: Hashable {
    func uniqued() -> [Element] { Array(Set(self)) }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CallHistoryView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView { CallHistoryView() }
    }
}
#endif

// MARK: - ChatService (채팅방 생성/조회 공용 유틸)

final class ChatService {
    static let shared = ChatService()
    private let db = Firestore.firestore()

    /// 두 사용자 간 고정 roomId(참여자 소팅 후 "_")
    private func roomId(myUid: String, otherUid: String) -> String {
        return [myUid, otherUid].sorted().joined(separator: "_")
    }

    /// 존재하면 반환, 없으면 생성 후 반환
    func getOrCreateRoom(with otherUid: String, completion: @escaping (String?, Error?) -> Void) {
        guard let myUid = Auth.auth().currentUser?.uid, !myUid.isEmpty else {
            completion(nil, NSError(domain: "auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "로그인이 필요합니다."]))
            return
        }
        let id = roomId(myUid: myUid, otherUid: otherUid)
        let ref = db.collection("chatRooms").document(id)

        ref.getDocument { snap, err in
            if let err = err {
                completion(nil, err); return
            }
            if let snap = snap, snap.exists {
                completion(id, nil); return
            }
            // 생성
            let payload: [String: Any] = [
                "participants": [myUid, otherUid],
                "createdAt": FieldValue.serverTimestamp(),
                "lastMessage": FieldValue.delete(),      // 아직 없음
                "lastTimestamp": FieldValue.serverTimestamp()
            ]
            ref.setData(payload, merge: true) { err in
                completion(err == nil ? id : nil, err)
            }
        }
    }
}

