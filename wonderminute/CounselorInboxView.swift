import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct CounselorInboxView: View {
    @State private var sessions: [CounselingSessionCell] = []
    @State private var listener: ListenerRegistration?    // ✅ @State로 변경
    private let db = Firestore.firestore()
    
    var body: some View {
        List {
            ForEach(sessions) { s in
                NavigationLink {
                    CounselorChatView(userId: s.userId)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.displayName)
                                .font(.headline)
                            Text(s.preview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if s.unread > 0 {
                            Text("\(s.unread)")
                                .font(.caption2).bold()
                                .padding(6)
                                .background(Color.red.opacity(0.9))
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }
                }
            }
        }
        .navigationTitle("상담 인박스")
        .onAppear { subscribe() }
        .onDisappear { unsubscribe() }
    }
    
    // Realtime subscribe
    private func subscribe() {
        let uid = Auth.auth().currentUser?.uid ?? ""
        guard uid == COUNSELOR_UID else { return }
        
        listener = db.collection("counselingSessions")
            .whereField("counselorId", isEqualTo: COUNSELOR_UID)
            .whereField("status", isEqualTo: "open")
            .order(by: "lastMessage.createdAt", descending: true)
            .addSnapshotListener { snap, err in
                if let err = err {
                    print("❌ [CounselorInbox] snapshot error:", err.localizedDescription)
                    return
                }
                guard let docs = snap?.documents else {
                    print("⚠️ [CounselorInbox] snapshot nil")
                    return
                }
                print("✅ [CounselorInbox] docs count =", docs.count)

                let rows: [CounselingSessionCell] = docs.map { d in
                    let last = d.get("lastMessage") as? [String:Any] ?? [:]
                    let unread = (d.get("unreadCounts") as? [String:Any])?["counselor"] as? Int ?? 0
                    let name = (d.get("userProfile") as? [String:Any])?["nickname"] as? String ?? "사용자"

                    print("• sessionId=\(d.documentID) lastText=\(last["text"] as? String ?? "-") unread=\(unread) name=\(name)")

                    return CounselingSessionCell(
                        id: d.documentID,
                        userId: d.documentID,
                        displayName: name,
                        preview: (last["text"] as? String) ?? "",
                        unread: unread
                    )
                }

                // ✅ 메인 스레드에서 상태 갱신
                DispatchQueue.main.async {
                    self.sessions = rows
                }
            }

    }
    
    private func unsubscribe() {
        listener?.remove()
        listener = nil
    }
}

struct CounselingSessionCell: Identifiable {
    let id: String
    let userId: String
    let displayName: String
    let preview: String
    let unread: Int
}
