import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct LiveChatSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var svc = LiveChatService()
    @State private var messages: [ChatMessage] = []
    @State private var text: String = ""
    @State private var firstSentBanner: Bool = false
    @State private var showEndConfirm: Bool = false
    
    private var userId: String { Auth.auth().currentUser?.uid ?? "unknown" }
    
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("상담하기")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)           // ⬅️ 백 라벨 화이트
                    }
                    
                    Spacer()
                    Button {
                        showEndConfirm = true                       // ⬅️ 즉시 종료 대신 알럿 표시
                    } label: {
                        Text("상담 종료하기")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)                // ⬅️ 그라데이션 위에서 잘 보이게
                    }
                    
                }
                
                Text("실시간 상담")
                    .font(.headline)
                    .foregroundStyle(.white)              // ⬅️ 제목 화이트
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(                                  // ⬅️ 원더미닛 그라데이션 적용
                LinearGradient(colors: [AppTheme.purple, AppTheme.blue],
                               startPoint: .leading, endPoint: .trailing)
            )
            .overlay(                                     // ⬅️ 하단 구분선(은은한 화이트)
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 0.6),
                alignment: .bottom
            )
            
            
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { m in
                            let isMe = (m.role == "user")
                            HStack(spacing: 8) {
                                if !isMe {    // 상담사(좌측)
                                    bubbleView(m.text, isMe: false)
                                    Spacer(minLength: 0)
                                } else {      // 사용자(우측)
                                    Spacer(minLength: 0)
                                    bubbleView(m.text, isMe: true)
                                }
                            }
                            .frame(maxWidth: .infinity)                 // ⬅️ 행이 화면폭을 꽉 쓰도록
                            .padding(.horizontal, 12)
                            .id(m.id)
                            
                            
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
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("메시지를 입력하세요", text: $text, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(false)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                
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
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [AppTheme.purple, AppTheme.blue],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(Divider(), alignment: .top)
            
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
        .alert("상담을 종료할까요?", isPresented: $showEndConfirm) {
            Button("취소", role: .cancel) { }
            Button("종료", role: .destructive) {
                Task {
                    await svc.closeSession(userId: userId)
                    do {
                        try await svc.deleteSessionCascade(userId: userId) // ⬅️ 방 데이터 전부 삭제
                    } catch {
                        print("❌ [EndChat] deleteSessionCascade failed:", error.localizedDescription)
                    }
                    dismiss()
                }
            }
            
        } message: {
            Text("종료 시 대화가 즉시 종료되며, 입력 내용은 서버에 보관되지 않습니다.")
        }
        
        .navigationBarBackButtonHidden(true)
    }
    
    @ViewBuilder
    private func bubbleView(_ text: String, isMe: Bool) -> some View {
        Text(text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isMe {
                        LinearGradient(colors: [AppTheme.purple, AppTheme.blue],
                                       startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
                    }
                }
            )
        
            .foregroundColor(isMe ? .white : .primary)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.78,  // 살짝 더 넓게
                   alignment: isMe ? .trailing : .leading)
    }
    


}

extension LiveChatService {
    /// counselingSessions/{userId} 문서 및 messages 서브컬렉션 전체 삭제
    func deleteSessionCascade(userId: String) async throws {
        let db = Firestore.firestore()
        let sessionRef = db.collection("counselingSessions").document(userId)

        // 1) 서브컬렉션(messages) 전체 삭제 (배치로 분할)
        let messagesRef = sessionRef.collection("messages")
        while true {
            // 한 번에 너무 많이 가져오지 않도록 제한
            let snap = try await messagesRef.limit(to: 450).getDocuments()
            if snap.documents.isEmpty { break }
            let batch = db.batch()
            for doc in snap.documents {
                batch.deleteDocument(doc.reference)
            }
            try await batch.commit()
        }

        // 2) 세션 문서 삭제
        try await sessionRef.delete()
    }
}
