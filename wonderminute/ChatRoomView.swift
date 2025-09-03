import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ChatRoomView: View {
    let roomId: String
    let otherNickname: String
    let otherPhotoURL: String?
    let otherUid: String
    @Environment(\.dismiss) private var dismiss                  // ✅ 추가

    @State private var messages: [ChatMessageLite] = []
    @State private var text: String = ""
    @State private var loading = true
    @State private var errMsg: String?
    @State private var listener: ListenerRegistration?

    // ✅ 나가기 관련 상태 추가
    @State private var showLeaveConfirm = false
    @State private var isLeaving = false
    // ✅ 키보드 포커스 상태
        @FocusState private var inputFocused: Bool
    
    // ✅ 자동 스크롤 튜닝용 상태
    @State private var atBottom: Bool = true
    @State private var unreadCount: Int = 0
    
    // ✅ 상대 읽음 시각 실시간 구독용
      @State private var otherReadAt: Timestamp?
      @State private var roomMetaListener: ListenerRegistration?
    
   
    
     private func markRead() {
         guard hasValidRoomId, myUid != "unknown" else { return }
         let roomRef = db.collection("chatRooms").document(roomId)
         roomRef.setData([
             "readAt": [myUid: FieldValue.serverTimestamp()],
             "unread": [myUid: 0]
         ], merge: true)
     }

    private let db = Firestore.firestore()
    private var myUid: String { Auth.auth().currentUser?.uid ?? "unknown" }
    private var hasValidRoomId: Bool {
        !roomId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var body: some View {
        VStack(spacing: 0) {
            // 상단 타이틀
            HStack(spacing: 12) {
                Avatar(urlString: otherPhotoURL, fallback: otherNickname)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(otherNickname).font(.subheadline.bold())
                    Text("대화 중").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider().opacity(0.2)


            // 메시지 리스트
            // 메시지 리스트
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(messages) { m in
                            let showRead = (m.id == lastReadMyMessageId)

                            ChatBubbleRow(message: m,
                                          isMine: m.senderId == myUid,
                                          showReadReceipt: showRead)          // ✅ 전달
                                .id(m.id)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 4)
                        }


                        // ✅ 바닥 센티넬: 보이면 atBottom=true, 사라지면 false
                        Color.clear
                            .frame(height: 1)
                            .id("BOTTOM_SENTINEL")
                            .onAppear {
                                atBottom = true
                                unreadCount = 0
                                markRead() // ✅ 최신까지 내려왔으면 읽음 처리
                            }
                            .onDisappear {
                                atBottom = false
                            }

                    }
                    .padding(.top, 4)

                }
                .background(GradientBackground().ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)   // ✅ 스크롤로도 키보드 내림 (iOS 16+)
                .onTapGesture {                             // ✅ 빈 공간 탭 시 키보드 내림
                    inputFocused = false
                }
                .onChange(of: messages.last?.id) { lastId in
                    dbg("🔄 messages changed lastId=\(lastId ?? "nil")")
                    guard let lastId = lastId else { return }
                    let lastIsMine = (messages.last?.senderId == myUid)

                    if lastIsMine || atBottom {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                        unreadCount = 0
                        markRead() // ✅ 내가 보냈거나 이미 바닥이면 읽음 처리
                    } else {
                        unreadCount += 1
                    }
                }

                
                .overlay(alignment: .bottomTrailing) {
                       if unreadCount > 0 {
                           Button {
                               let targetId = messages.last?.id ?? "BOTTOM_SENTINEL"
                               withAnimation { proxy.scrollTo(targetId, anchor: .bottom) }
                               unreadCount = 0
                               markRead()
                           } label: {
                               HStack(spacing: 6) {
                                   Image(systemName: "arrow.down.circle.fill")
                                       .font(.title3)
                                   Text("새 메시지 \(unreadCount)")
                                       .font(.caption).bold()
                               }
                               .padding(.vertical, 8)
                               .padding(.horizontal, 12)
                               .background(.ultraThinMaterial, in: Capsule())
                           }
                           .padding(.trailing, 12)
                           .padding(.bottom, 12) // 입력창 위로 띄우기
                       }
                   }


            }


            // 입력창
            HStack(spacing: 8) {
                TextField("메시지를 입력하세요", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .disabled(loading)
                    .focused($inputFocused)
                Button { send() } label: {
                    Text("전송").bold()
                }
                .disabled(!hasValidRoomId || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading)

            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .contentShape(Rectangle())        // ✅ 빈 여백까지 탭 영역으로
        .onTapGesture { inputFocused = false }
        .navigationTitle("") // 커스텀 헤더 사용
        .navigationBarTitleDisplayMode(.inline)
        // ✅ 상단 우측 '나가기' 버튼 (문 열리는 아이콘)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showLeaveConfirm = true
                } label: {
                    Image(systemName: "door.right.hand.open") // iOS 17+ (대체: "rectangle.portrait.and.arrow.right")
                }
                .disabled(isLeaving || !hasValidRoomId)
                .accessibilityLabel("채팅방 나가기")
            }
        }
        .onAppear {
            dbg("onAppear hasValidRoomId=\(hasValidRoomId) roomId=\(roomId)")
            if hasValidRoomId {
                subscribe()
                // ✅ room 메타(상대 readAt) 구독
                roomMetaListener?.remove()
                roomMetaListener = db.collection("chatRooms").document(roomId)
                    .addSnapshotListener { snap, _ in
                        guard let data = snap?.data() else { return }
                        if let map = data["readAt"] as? [String: Any] {
                            // 상대 uid의 readAt만 추출
                            if let ts = map[otherUid] as? Timestamp {
                                otherReadAt = ts
                            } else if let mv = map[otherUid] as? [String: Any],
                                      let sec = mv["seconds"] as? Int64 {
                                otherReadAt = Timestamp(seconds: sec, nanoseconds: 0)
                            }
                        }
                    }
            } else {
                loading = false
                dbg("onAppear skip subscribe (invalid roomId)")
            }
        }
        .onDisappear {
            listener?.remove()
            roomMetaListener?.remove()   // ✅ 추가
        }


        // ✅ 나가기 확인 알림
        .alert("채팅방 나가기", isPresented: $showLeaveConfirm) {
            Button("취소", role: .cancel) {}
            Button("나가기", role: .destructive) { performLeave() }
        } message: {
            Text("이 채팅방에서 나가시겠습니까?")
        }

        // 기존 오류 알림 유지
        .alert("오류", isPresented: .constant(errMsg != nil), actions: {
            Button("확인") { errMsg = nil }
        }, message: {
            Text(errMsg ?? "")
        })
    }


    private func subscribe() {
        guard hasValidRoomId else { dbg("subscribe() aborted: invalid roomId"); return }
        loading = true
        listener?.remove()
        dbg("subscribe() attach listener roomId=\(roomId)")

        listener = db.collection("chatRooms").document(roomId)
            .collection("messages")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener(includeMetadataChanges: true) { snap, err in
                if let err = err {
                    dbg("🔥 snapshot error: \(err.localizedDescription)")
                    DispatchQueue.main.async {
                        errMsg = err.localizedDescription
                        loading = false
                    }
                    return
                }
                guard let snap = snap else {
                    dbg("⚠️ snapshot is nil")
                    return
                }

                let meta = snap.metadata
                dbg("📥 snapshot event: count=\(snap.documents.count) changes=\(snap.documentChanges.count) isFromCache=\(meta.isFromCache) hasPendingWrites=\(meta.hasPendingWrites)")

                if _firstSnapshot && snap.documents.isEmpty && meta.isFromCache && !meta.hasPendingWrites {
                    dbg("⚠️ first snapshot is EMPTY & from CACHE (서버 스냅샷 대기 가능성)")
                }
                if _firstSnapshot && !meta.hasPendingWrites && !meta.isFromCache && snap.documents.isEmpty {
                    dbg("⚠️ first snapshot is EMPTY & from SERVER (실제로 메시지가 없음)")
                }
                _firstSnapshot = false

                // 각 change 상세
                if !snap.documentChanges.isEmpty {
                    for ch in snap.documentChanges {
                        dbg(" • change=\(ch.type) id=\(ch.document.documentID) hasPendingWrites=\(ch.document.metadata.hasPendingWrites)")
                    }
                }

                let arr: [ChatMessageLite] = snap.documents.compactMap { ChatMessageLite(doc: $0) }
                let lastTs = arr.last?.timestamp?.dateValue().description ?? "nil"
                DispatchQueue.main.async {
                    messages = arr
                    loading = false
                    dbg("✅ UI updated messages.count=\(messages.count) lastTs=\(lastTs)")
                }
            }
    }





    private func send() {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasValidRoomId else { dbg("send() aborted: invalid roomId"); return }
        guard !content.isEmpty, let me = Auth.auth().currentUser?.uid else { dbg("send() aborted: empty content or no uid"); return }

        let roomRef = db.collection("chatRooms").document(roomId)
        let msgRef  = roomRef.collection("messages").document()

        let now = Timestamp(date: Date())
        dbg("✉️ send() id=\(msgRef.documentID) content='\(content)' now=\(now.seconds).\(now.nanoseconds)")

        let payload: [String: Any] = [
            "senderId": me,
            "content": content,
            "timestamp": now,
            "serverTimestamp": FieldValue.serverTimestamp()
        ]

        DispatchQueue.main.async {
            let temp = ChatMessageLite(id: msgRef.documentID, senderId: me, content: content, timestamp: now)
            messages.append(temp)
            dbg("🧩 optimistic append id=\(temp.id) messages.count=\(messages.count)")
        }

        msgRef.setData(payload) { err in
            if let err = err {
                dbg("🔥 send() setData error: \(err.localizedDescription)")
                errMsg = err.localizedDescription
                return
            }
            dbg("✅ send() setData success id=\(msgRef.documentID)")

            roomRef.setData([
                "lastMessage": content,
                "lastTimestamp": now,
                "lastTimestampServer": FieldValue.serverTimestamp(),
                "readAt": [myUid: FieldValue.serverTimestamp()],            // 내 읽음 갱신
                "unread": [myUid: 0, otherUid: FieldValue.increment(1.0)],  // ✅ 내 unread=0, 상대 unread+1
                "leftAt.\(myUid)": FieldValue.delete()
            ], merge: true) { e in

                if let e = e {
                    dbg("⚠️ update room summary error: \(e.localizedDescription)")
                } else {
                    dbg("✅ room summary updated")
                }
            }
            text = ""
        }
    }
    
    // ✅ 새 나가기: participants 유지, 방 문서에 leftAt.{uid} 만 기록
    // ✅ 둘 다 나가면 messages 삭제 후 room 문서 삭제
    private func performLeave() {
        guard hasValidRoomId, myUid != "unknown" else { return }
        isLeaving = true
        let roomRef = db.collection("chatRooms").document(roomId)

        // 1) 내 leave 시각 기록
        roomRef.setData([
            "leftAt": [myUid: FieldValue.serverTimestamp()]
        ], merge: true) { err in
            if let err = err {
                isLeaving = false
                errMsg = "나가기 실패: \(err.localizedDescription)"
                return
            }
            // 2) 둘 다 나갔는지 확인 후 삭제
            roomRef.getDocument { snap, e in
                defer { isLeaving = false }
                if let e = e { dbg("⚠️ leave check error: \(e.localizedDescription)"); dismiss(); return }
                guard let data = snap?.data() else { dismiss(); return }

                let participants = (data["participants"] as? [String]) ?? []
                let lastTs = data["lastTimestamp"] as? Timestamp
                let leftMap = data["leftAt"] as? [String: Any] ?? [:]
                let leftTsForAll = participants.compactMap { uid in
                    if let ts = leftMap[uid] as? Timestamp { return ts }
                    if let m = leftMap[uid] as? [String: Any], let t = m["seconds"] as? Int64 { return Timestamp(seconds: t, nanoseconds: 0) }
                    return nil
                }

                // 둘 다(모든 참가자) leftAt 존재 + 마지막 메시지가 두 사람이 나간 뒤에 생성되지 않음
                let allLeft = leftTsForAll.count == participants.count
                let maxLeft = leftTsForAll.max(by: { $0.dateValue() < $1.dateValue() })
                let deletable = allLeft && (lastTs == nil || (maxLeft != nil && lastTs!.dateValue() <= maxLeft!.dateValue()))

                if deletable {
                    // messages 서브컬렉션 삭제(배치, 100개 단위)
                    deleteMessagesThenRoom(roomRef: roomRef) { _ in
                        dbg("🧹 room fully deleted: \(roomId)")
                        dismiss()
                    }
                } else {
                    dismiss()
                }
            }
        }
    }

    // 🔧 메시지 먼저 지운 뒤 room 삭제(간단 배치 반복)
    private func deleteMessagesThenRoom(roomRef: DocumentReference, completion: @escaping (Error?) -> Void) {
        let msgs = roomRef.collection("messages").order(by: "timestamp").limit(to: 100)
        msgs.getDocuments { snap, err in
            if let err = err { completion(err); return }
            guard let docs = snap?.documents, !docs.isEmpty else {
                // 더 이상 메시지가 없으면 room 삭제
                roomRef.delete(completion: completion)
                return
            }
            let batch = roomRef.firestore.batch()
            docs.forEach { batch.deleteDocument($0.reference) }
            batch.commit { e in
                if let e = e { completion(e); return }
                // 남은 메시지 반복 삭제
                deleteMessagesThenRoom(roomRef: roomRef, completion: completion)
            }
        }
    }




    // ✅ 로그 유틸(타임스탬프+파일/라인)
    private static let _tsFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    @State private var _firstSnapshot = true

    private func dbg(_ msg: String, file: String = #fileID, line: Int = #line) {
        let ts = Self._tsFmt.string(from: Date())
        print("📡[ChatRoomView][\(ts)] \(msg) (\(file):\(line))")
    }
    // 상대가 읽은 '마지막 내 메시지' id (상대 readAt 이전/같은 시간의 내 메시지 중 가장 최근 것)
    private var lastReadMyMessageId: String? {
        guard let or = otherReadAt?.dateValue() else { return nil }
        return messages
            .filter { $0.senderId == myUid && ($0.timestamp?.dateValue() ?? .distantPast) <= or }
            .last?.id
    }


}

// MARK: - 수동 파싱 모델

struct ChatMessageLite: Identifiable {
    let id: String
    let senderId: String
    let content: String
    let timestamp: Timestamp?

    init?(doc: QueryDocumentSnapshot) {
        let data = doc.data()
        guard
            let senderId = data["senderId"] as? String,
            let content = data["content"] as? String
        else { return nil }

        self.id = doc.documentID
        self.senderId = senderId
        self.content = content
        self.timestamp = data["timestamp"] as? Timestamp
    }
}

// MARK: - UI Row

private struct ChatBubbleRow: View {
    let message: ChatMessageLite
    let isMine: Bool
    var showReadReceipt: Bool = false   // ✅ 추가 기본값

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
            HStack {
                if isMine { Spacer() }
                Text(message.content)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(isMine ? Color.white.opacity(0.9) : Color.white.opacity(0.2))
                    .foregroundStyle(isMine ? .black : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.15), lineWidth: 1)
                    )
                if !isMine { Spacer() }
            }
            // ✅ 내 마지막 메시지에만 "읽음" 표시
            if isMine && showReadReceipt {
                Text("읽음")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
    }
}


extension ChatMessageLite {
    init(id: String, senderId: String, content: String, timestamp: Timestamp?) {
        self.id = id
        self.senderId = senderId
        self.content = content
        self.timestamp = timestamp
    }
}

