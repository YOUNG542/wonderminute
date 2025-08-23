import Foundation
import FirebaseFirestore
import FirebaseAuth

final class MatchingManager: ObservableObject {
    private let db = Firestore.firestore()
    private var userListener: ListenerRegistration?
    private var roomListener: ListenerRegistration?

    deinit { stop() }
    func stop() { userListener?.remove(); userListener = nil; roomListener?.remove(); roomListener = nil }

    func startMatching(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ 현재 로그인한 사용자 없음")
            completion(false); return
        }

        // 서버 소스 기준 유령 상태 점검
        db.collection("users").document(uid).getDocument(source: .server) { [weak self] snap, err in
            if let err = err { print("⚠️ activeRoomId 조회 에러:", err.localizedDescription) }
            let roomId = (snap?.get("activeRoomId") as? String) ?? ""
            let phase  = (snap?.get("matchPhase") as? String) ?? "idle"

            if phase == "matched", !roomId.isEmpty {
                print("🔁 서버상 이미 matched 상태 → 성공 처리")
                completion(true); return
            }

            self?.enqueueAndListenUser(completion: completion)
        }
    }

    private func enqueueAndListenUser(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else { completion(false); return }
        let uid = user.uid

        func attempt(_ left: Int) {
            // ✅ 초기 토큰 한번 갱신(초기 흔들림 방지)
            user.getIDToken { _, tokenErr in
                if let tokenErr = tokenErr {
                    print("⚠️ IDToken 갱신 실패:", tokenErr.localizedDescription)
                }

                // ✅ 1) 내 성별 & 선호 성별 읽기
                self.db.collection("users").document(uid).getDocument(source: .server) { [weak self] userSnap, uErr in
                    if let uErr = uErr {
                        print("⚠️ 사용자 문서 조회 실패:", uErr.localizedDescription)
                        if left > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { attempt(left - 1) }
                        } else {
                            completion(false)
                        }
                        return
                    }

                    guard let myGender = userSnap?.get("gender") as? String else {
                        print("❌ 프로필에 gender가 없습니다. 가입 플로우를 확인하세요.")
                        completion(false); return
                    }

                    let pref = (userSnap?.get("wantGenderPreference") as? String) ?? "auto"
                    let wantGender: String = {
                        if pref == "남자" || pref == "여자" { return pref }
                        if pref == "all" { return "all" }
                        return (myGender == "남자") ? "여자" : "남자"
                    }()

                    let queueRef = self?.db.collection("matchingQueue").document(uid)
                    let data: [String: Any] = [
                        "uid": uid,
                        "status": "waiting",
                        "createdAt": FieldValue.serverTimestamp(),
                        "heartbeatAt": FieldValue.serverTimestamp(),
                        "gender": myGender,
                        "wantGender": wantGender
                    ]

                    queueRef?.setData(data, merge: true) { [weak self] err in
                        if let err = err as NSError? {
                            print("❌ 대기열 등록 실패(code=\(err.code)):", err.localizedDescription)
                            if left > 0 && (err.domain == FirestoreErrorDomain || err.code == 7 || err.code == 14) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { attempt(left - 1) }
                                return
                            }
                            completion(false); return
                        }

                        print("✅ 대기열 등록 완료 (gender=\(myGender), wantGender=\(wantGender))")
                        self?.userListener?.remove()
                        self?.userListener = self?.db.collection("users").document(uid)
                            .addSnapshotListener(includeMetadataChanges: false) { [weak self] snap, err in
                                if let err = err {
                                    print("⚠️ user listen error:", err.localizedDescription)
                                    return
                                }
                                let phase = (snap?.get("matchPhase") as? String) ?? "idle"
                                let room  = (snap?.get("activeRoomId") as? String) ?? ""
                                print("👀 user status phase=\(phase) room=\(room)")

                                guard phase == "matched", !room.isEmpty else { return }

                                self?.verifyRoomContainsMe(roomId: room, uid: uid) { ok in
                                    if ok {
                                        self?.userListener?.remove(); self?.userListener = nil
                                        completion(true)
                                    } else {
                                        print("⚠️ room 존재/참가 확인 실패 → 대기 유지")
                                    }
                                }
                            }
                    }
                }
            }
        }

        attempt(2) // ✅ 총 3회(원호 + 2회 재시도)
    }


    private func verifyRoomContainsMe(roomId: String, uid: String, done: @escaping (Bool)->Void) {
        db.collection("matchedRooms").document(roomId).getDocument { snap, _ in
            guard let d = snap?.data() else { return done(false) }
            let users = (d["users"] as? [String]) ?? [d["user1"], d["user2"]].compactMap { $0 as? String }
            done(users.contains(uid))
        }
    }
}
