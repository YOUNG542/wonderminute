import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

// 고정 상담사 UID
let COUNSELOR_UID = "SIaBmD28EwdVX2POrNOxtOFCKYk1"

struct ChatMessage: Identifiable, Codable {
    var id: String
    var text: String
    var role: String // "user" | "counselor"
    var createdAt: Date
}

final class LiveChatService: ObservableObject {
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    // 세션 문서 경로: counselingSessions/{userId}
    private func sessionRef(for userId: String) -> DocumentReference {
        db.collection("counselingSessions").document(userId)
    }
    private func messagesRef(for userId: String) -> CollectionReference {
        sessionRef(for: userId).collection("messages")
    }
    
    func sendMessage(as role: String, to userId: String, text: String) async throws {
        guard let senderUid = Auth.auth().currentUser?.uid else {
            print("❌ [LiveChatService] sendMessage aborted: sender uid nil")
            throw NSError(domain: "LiveChat", code: -1, userInfo: [NSLocalizedDescriptionKey: "Auth missing"])
        }
        print("🟨 [LiveChatService] sendMessage begin sender=\(senderUid) role=\(role) to userId=\(userId) text='\(text)'")

        do {
            try await sessionRef(for: userId).setData([
                "userId": userId,
                "counselorId": COUNSELOR_UID,
                "status": "open",
                "openedAt": FieldValue.serverTimestamp()
            ], merge: true)
            print("✅ [LiveChatService] session upsert OK")
        } catch {
            print("❌ [LiveChatService] session upsert FAIL:", error.localizedDescription)
            throw error
        }

        do {
            try await messagesRef(for: userId).addDocument(data: [
                "text": text,
                "role": role,
                "createdAt": FieldValue.serverTimestamp()
            ])
            print("✅ [LiveChatService] add message OK")
        } catch {
            print("❌ [LiveChatService] add message FAIL:", error.localizedDescription)
            throw error
        }
    }

    
    /// 채팅 구독
    func listenMessages(userId: String, onChange: @escaping ([ChatMessage]) -> Void) {
        stop()
        listener = messagesRef(for: userId)
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else { return }
                let items: [ChatMessage] = docs.compactMap { d in
                    let data = d.data()
                    let ts = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    return ChatMessage(
                        id: d.documentID,
                        text: (data["text"] as? String) ?? "",
                        role: (data["role"] as? String) ?? "user",
                        createdAt: ts
                    )
                }
                DispatchQueue.main.async { // ✅ 추가: UI 업데이트는 메인에서
                    onChange(items)
                }
            }

    }
    
    /// 읽음 카운트 초기화 (서버 HTTPS)
    func markRead(userId: String, role: String) async {
        do {
            var req = URLRequest(url: URL(string: "https://us-central1-wonderminute-7a4c9.cloudfunctions.net/readCounseling")!)
            req.httpMethod = "POST"
            req.addValue("application/json", forHTTPHeaderField: "Content-Type")
            let token = try await Auth.auth().currentUser?.getIDToken() ?? ""
            req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["userId": userId, "role": role])
            _ = try await URLSession.shared.data(for: req)
        } catch {
            print("markRead error:", error.localizedDescription)
        }
    }
    
    func closeSession(userId: String) async {
        do {
            let _ = try await Functions.functions().httpsCallable("closeCounselingSession").call(["userId": userId])
        } catch {
            print("closeSession error:", error.localizedDescription)
        }
    }
    
    func stop() { listener?.remove(); listener = nil }
}


