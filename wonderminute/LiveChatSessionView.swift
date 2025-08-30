import SwiftUI
import FirebaseAuth

struct LiveChatSessionView: View {
    @StateObject private var svc = LiveChatService()
    @State private var messages: [ChatMessage] = []
    @State private var text: String = ""
    @State private var firstSentBanner: Bool = false
    
    private var userId: String { Auth.auth().currentUser?.uid ?? "unknown" }
    
    var body: some View {
        VStack(spacing: 0) {
            // 상단 바 - 종료 버튼
            HStack {
                Text("실시간 상담")
                    .font(.headline)
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
                                if m.role == "user" { Spacer() }
                                let isMe = (m.role == "user")
                                Text(m.text)
                                    .padding(10)
                                    .background(isMe ? Color.blue.opacity(0.9) : Color.gray.opacity(0.2)) // ✅ 고정 대비 색
                                    .foregroundColor(isMe ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                if m.role != "user" { Spacer() }
                            }
                            .padding(.horizontal, 12)
                            .id(m.id) // ✅ 추가: 마지막 메시지로 스크롤되도록 고유 id 부여
                        }

                        if firstSentBanner {
                            Text("상담사에게 전송되었습니다. 잠시만 기다려주세요!")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        }
                    }
                    .onChange(of: messages.count) { _ in
                        if let last = messages.last?.id {
                            withAnimation {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            Divider()
            
            // 입력 바
            HStack {
                TextField("메시지를 입력하세요", text: $text)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task {
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let myUid = Auth.auth().currentUser?.uid ?? "nil"
                        print("🟩 [UserChat] send tap uid=\(myUid) to userId=\(userId) text='\(t)'")
                        do {
                            try await svc.sendMessage(as: "user", to: userId, text: t)
                            print("✅ [UserChat] send OK")
                            text = ""
                            if messages.filter({ $0.role == "user" }).count <= 1 {
                                firstSentBanner = true
                            }
                        } catch {
                            print("❌ [UserChat] send FAIL:", error.localizedDescription)
                        }
                    }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .padding(8)
                }

            }
            .padding(.all, 8)
            .background(Color(.systemBackground))
        }
        .onAppear {
            svc.listenMessages(userId: userId) { items in
                messages = items
            }
            Task { await svc.markRead(userId: userId, role: "user") }
        }
        .onDisappear {
            svc.stop()
        }
    }
}
