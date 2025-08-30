import SwiftUI
import FirebaseAuth

struct CounselorChatView: View {
    let userId: String
    @StateObject private var svc = LiveChatService()
    @State private var messages: [ChatMessage] = []
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("상담 - \(userId.prefix(6))…").font(.headline)
                Spacer()
                Button {
                    Task { await svc.closeSession(userId: userId) }
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
            }
            .padding()
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { m in
                            HStack {
                                if m.role == "counselor" { Spacer() }
                                let isMe = (m.role == "counselor")
                                Text(m.text)
                                    .padding(10)
                                    .background(isMe ? Color.blue.opacity(0.9) : Color.gray.opacity(0.2)) // ✅ 고정 대비 색
                                    .foregroundColor(isMe ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                if m.role != "counselor" { Spacer() }
                            }
                            .padding(.horizontal, 12)
                            .id(m.id)
                        }
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last?.id {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }

            Divider()
            HStack {
                TextField("답장을 입력하세요", text: $text)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let myUid = Auth.auth().currentUser?.uid ?? "nil"
                        print("🟦 [CounselorChat] send tap uid=\(myUid) to userId=\(userId) text='\(t)'")
                        do {
                            try await svc.sendMessage(as: "counselor", to: userId, text: t)
                            print("✅ [CounselorChat] send OK")
                            text = ""
                        } catch {
                            print("❌ [CounselorChat] send FAIL:", error.localizedDescription)
                        }
                    }
                } label: {
                    Image(systemName: "paperplane.fill").padding(8)
                }

            }
            .padding(8)
        }
        .onAppear {
            svc.listenMessages(userId: userId) { items in
                messages = items
            }
            Task { await svc.markRead(userId: userId, role: "counselor") }
        }
        .onDisappear { svc.stop() }
    }
}
