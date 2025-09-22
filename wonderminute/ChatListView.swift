import SwiftUI
import FirebaseAuth
import FirebaseFirestore
// import FirebaseFirestoreSwift   // ❌ 제거

struct ChatListView: View {
    init() {
        if #available(iOS 15.0, *) {
            UITableView.appearance().sectionHeaderTopPadding = 0
            UITableView.appearance().contentInset.top = 0
            UITableView.appearance().scrollIndicatorInsets = .zero                  // ⬅️ 추가
            UITableView.appearance().tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0.01)) // ⬅️ 추가
            UITableViewHeaderFooterView.appearance().backgroundConfiguration = UIBackgroundConfiguration.clear()
        } else {
            UITableViewHeaderFooterView.appearance().tintColor = .clear
            UITableViewHeaderFooterView.appearance().backgroundView = UIView()
        }

    }

    @State private var rows: [ChatListRow] = []
    @State private var loading = true
    @State private var error: String?
    @State private var listener: ListenerRegistration?
    
    @State private var pushChat = false
    @State private var activeRoomId: String?
    @State private var activeOtherNickname: String = ""
    @State private var activeOtherPhotoURL: String?
    @State private var activeOtherUid: String = ""
    
    @State private var confirmLeaveRoomId: String?
    
    
    private let db = Firestore.firestore()
    private var myUid: String { Auth.auth().currentUser?.uid ?? "" }
    
    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            
            GeometryReader { geo in
                // 큰 화면에서는 (화면폭 - 목표폭)/2 만큼 여백, 작은 화면에서는 12pt 고정
                let minSidePadding: CGFloat = 28                 // 🔼 여백을 살짝 더 넉넉하게
                let targetWidth: CGFloat = 420
                let clampedTarget = min(targetWidth, geo.size.width - (minSidePadding * 2))
                let inset = max((geo.size.width - clampedTarget) / 2, minSidePadding)

                
                List {
                    // programmatic navigation anchor
                    NavigationLink(isActive: $pushChat) {
                        Group {
                            if let rid = activeRoomId, !rid.isEmpty {
                                ChatRoomView(roomId: rid,
                                             otherUid: activeOtherUid,
                                             initialNickname: activeOtherNickname,
                                             initialPhotoURL: activeOtherPhotoURL)
                                
                            } else {
                                EmptyView()
                            }
                        }
                    } label: { EmptyView() }
                        .frame(width: 0, height: 0)
                        .hidden()
                    
                    
                    // 🔒 섹션 헤더가 만드는 상단 흰 띠를 원천 차단: 커스텀 헤더 행으로 대체
                    HStack {
                        Text("최근 채팅").font(.headline)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset))
                    .padding(.top, 4)

                    if loading {
                        HStack {
                            Spacer()
                            ProgressView("불러오는 중…").tint(.white)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                    
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .listRowBackground(Color.clear)
                    }
                    
                    if rows.isEmpty && !loading && error == nil {
                        Text("최근 채팅이 없습니다.")
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                    
                    ForEach(rows) { r in
                        Button {
                            // 이전 상태 초기화
                            pushChat = false
                            activeRoomId = nil
                            
                            activeOtherNickname = r.otherNickname
                            activeOtherPhotoURL = r.otherPhotoURL
                            activeOtherUid = r.otherUid
                            
                            DispatchQueue.main.async {
                                activeRoomId = r.roomId  // 먼저 세팅
                                pushChat = !r.roomId.isEmpty
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(urlString: r.otherPhotoURL, fallback: r.otherNickname)
                                    .frame(width: 36, height: 36)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(r.otherNickname)
                                        .font(.subheadline).bold()
                                        .foregroundStyle(.primary)
                                    if r.isOtherTyping {
                                        Text("입력 중…")
                                            .font(.caption)
                                            .foregroundStyle(.green)
                                    } else {
                                        Text(r.lastMessage ?? "대화를 시작해 보세요")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                VStack(alignment: .trailing, spacing: 6) {
                                    if let ts = r.lastTimestamp?.dateValue() {
                                        Text(ts.formatted(date: .omitted, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    if r.unreadCount > 0 {   // ✅ 미읽음 뱃지
                                        Text("\(r.unreadCount)")
                                            .font(.caption2.bold())
                                            .padding(.vertical, 3)
                                            .padding(.horizontal, 6)
                                            .background(.blue.opacity(0.9), in: Capsule())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            // 🔑 행 전체를 히트영역으로 확장
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        
                        .buttonStyle(.plain)
                           .listRowBackground(Color.clear)
                           .listRowInsets(EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset)) // ⬅️ 추가
                           .listRowSeparator(.visible)
                           .listRowSeparatorTint(.white.opacity(0.35))
                        // ✅ 스와이프 액션: 쓰레기통 → 방 나가기
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                confirmLeaveRoomId = r.roomId
                            } label: {
                                Label("나가기", systemImage: "trash")
                            }
                        }
                        
                    }
                    
                }
                .scrollContentBackground(.hidden)         // 리스트 기본 배경 차단
                .background(Color.clear)                  // 리스트 자체 배경 투명
                .listStyle(.plain)
                .listSectionSpacing(.compact)
                .ignoresSafeArea(edges: .top)             // ✅ 상단 safe area 자체 무시
                .onAppear {
                    // ✅ 스크롤뷰 자동 인셋 제거 (상단 흰 띠 원인)
                    UIScrollView.appearance().contentInsetAdjustmentBehavior = .never
                    
                    let appearance = UINavigationBarAppearance()
                    appearance.configureWithTransparentBackground()
                    appearance.backgroundColor = .clear
                    appearance.shadowColor = .clear                 // ⬅️ 추가: 하단 1px 라인 제거
                    appearance.shadowImage = UIImage()              // ⬅️ 추가: 보수적 차단
                    UINavigationBar.appearance().standardAppearance = appearance
                    UINavigationBar.appearance().scrollEdgeAppearance = appearance
                    UINavigationBar.appearance().compactAppearance = appearance // ⬅️ 추가: compact에서도 동일
                    
                }
                .onDisappear {
                    UIScrollView.appearance().contentInsetAdjustmentBehavior = .automatic
                }
                .navigationBarTitle("채팅", displayMode: .inline)
                
                
            }
            .onAppear {
                // ✅ 네비게이션바 높이만큼 자동으로 넣는 상단 인셋 제거
                UIScrollView.appearance().contentInsetAdjustmentBehavior = .never
                subscribe()
            }
            .onDisappear {
                // ✅ 다른 화면에 영향 가지 않게 원복
                UIScrollView.appearance().contentInsetAdjustmentBehavior = .automatic
                listener?.remove()
            }
        }
        
        // ✅ 방 나가기 확인 알림
        .alert("채팅방 나가기", isPresented: .constant(confirmLeaveRoomId != nil)) {
            Button("취소", role: .cancel) { confirmLeaveRoomId = nil }
            Button("나가기", role: .destructive) {
                if let rid = confirmLeaveRoomId {
                    leaveRoom(roomId: rid)
                }
                confirmLeaveRoomId = nil
            }
        } message: {
            Text("이 채팅방에서 나가시겠습니까?")
        }
        
    }
    
    
    // MARK: - Firestore
    
    private func subscribe() {
        guard !myUid.isEmpty else {
            self.error = "로그인이 필요합니다."
            self.loading = false
            return
        }
        loading = true
        error = nil
        listener?.remove()
        
        listener = db.collection("chatRooms")
            .whereField("participants", arrayContains: myUid)
            .order(by: "lastTimestamp", descending: true)
            .addSnapshotListener { snap, err in
                if let err = err {
                    self.error = err.localizedDescription
                    self.loading = false
                    return
                }
                
                // ✅ 수동 파싱
                let rooms: [ChatRoomLite] = snap?.documents.compactMap { ChatRoomLite(doc: $0) } ?? []
                let otherUids = rooms.compactMap { room in
                    room.participants.first(where: { $0 != myUid })
                }
                
                fetchProfiles(uids: otherUids) { profiles in
                    let mapped = rooms
                        // ✅ 1) 내가 나가기 전의 메시지가 있어야만 보이도록
                        .filter { room in
                            let last = room.lastTimestampServer ?? room.lastTimestamp
                            let myLeft = room.leftAt[myUid]
                            let decision: Bool = {
                                if let myLeft, let last {
                                    return last.dateValue() > myLeft.dateValue()
                                } else if room.lastMessage == nil {
                                    return false
                                } else {
                                    return true
                                }
                            }()

                            log("""
                            🔎 FILTER room=\(room.id)
                              • lastServer=\(String(describing: room.lastTimestampServer?.dateValue()))
                              • lastClient=\(String(describing: room.lastTimestamp?.dateValue()))
                              • usedLast=\(String(describing: last?.dateValue()))
                              • myLeft=\(String(describing: myLeft?.dateValue()))
                              • lastMessage=\(String(describing: room.lastMessage))
                              • => keep=\(decision)
                            """)
                            return decision
                        }
                        .map { room -> ChatListRow in
                            let other = room.participants.first(where: { $0 != myUid }) ?? ""
                            let p = profiles[other]
                            let unread = room.unread[myUid] ?? 0
                            let isTyping = room.typing[other] ?? false
                            return ChatListRow(
                                id: room.id,
                                roomId: room.id,
                                otherUid: other,
                                otherNickname: p?.nickname ?? "(알 수 없음)",
                                otherPhotoURL: p?.photoURL,
                                lastMessage: room.lastMessage,
                                // ✅ 리스트의 시각 표시에 무엇을 쓰는지 명확히
                                lastTimestamp: room.lastTimestampServer ?? room.lastTimestamp,
                                unreadCount: unread,
                                isOtherTyping: isTyping
                            )
                        }

                    self.rows = mapped
                    self.loading = false
                    log("📥 subscribe done. rows.count=\(mapped.count)")
                }

            }
    }
    
    /// users/{uid} 프로필 일괄 조회 (IN 쿼리, 10개씩)
    private func fetchProfiles(uids: [String], completion: @escaping ([String: UserProfileLight]) -> Void) {
        let uniq = Array(Set(uids)).filter { !$0.isEmpty }
        guard !uniq.isEmpty else { completion([:]); return }
        
        var result: [String: UserProfileLight] = [:]
        let chunks = uniq.chunked(into: 10)
        let group = DispatchGroup()
        
        for c in chunks {
            group.enter()
            db.collection("users")
                .whereField(FieldPath.documentID(), in: c)
                .getDocuments { snap, err in
                    defer { group.leave() }
                    guard err == nil, let docs = snap?.documents else { return }
                    for d in docs {
                        let data = d.data()
                        let nick = (data["nickname"] as? String) ?? "(알 수 없음)"
                        
                        // 🔧 다양한 키 이름을 모두 허용 (저장 스키마 차이 대응)
                        let photo = (data["photoURL"] as? String)
                        ?? (data["photoUrl"] as? String)
                        ?? (data["profileImageUrl"] as? String)
                        ?? (data["ProfileImageUrl"] as? String)   // 기존 키도 마지막에 고려
                        
                        result[d.documentID] = UserProfileLight(id: d.documentID, nickname: nick, photoURL: photo)
                        
                    }
                }
        }
        group.notify(queue: .main) { completion(result) }
    }
    
    private func leaveRoom(roomId: String) {
        guard !myUid.isEmpty else { return }
        let roomRef = db.collection("chatRooms").document(roomId)

        log("🚪 leaveRoom start myUid=\(myUid) roomId=\(roomId)")
        // 1) 내 leave 시각 기록
        log("📝 setData leftAt.\(myUid)=serverTimestamp() (merge:true)")

        log("🚪 leaveRoom start myUid=\(myUid) roomId=\(roomId)")

        // 1) 내 leave 시각 안전 기록
        log("📝 updateData leftAt[\(myUid)]=serverTimestamp()")
        roomRef.updateData([
            FieldPath(["leftAt", myUid]): FieldValue.serverTimestamp()
        ]) { err in
            if let err = err {
                self.error = "방 나가기 실패: \(err.localizedDescription)"
                log("🔥 updateData leftAt error: \(err.localizedDescription)")
                return
            }
            log("✅ updateData leftAt success. Fetching server snapshot…")

            // 2) 둘 다 나갔는지 확인 후 삭제 (서버 스냅샷)
            roomRef.getDocument(source: .server) { snap, e in
                if let e = e { log("🔥 getDocument(.server) error: \(e.localizedDescription)"); return }
                guard let snap = snap, let data = snap.data() else { log("⚠️ nil snap/data"); return }

                let participants = (data["participants"] as? [String]) ?? []
                let leftMap = data["leftAt"] as? [String: Any] ?? [:]
                let leftTsForAll: [Timestamp] = participants.compactMap { uid in
                    if let ts = leftMap[uid] as? Timestamp { return ts }
                    if let m = leftMap[uid] as? [String: Any], let sec = m["seconds"] as? Int64 {
                        return Timestamp(seconds: sec, nanoseconds: 0)
                    }
                    return nil
                }

                let allLeft = leftTsForAll.count == participants.count

                log("""
                🧮 Decision
                  • allLeft=\(allLeft) (leftTsForAll.count=\(leftTsForAll.count), participants.count=\(participants.count))
                """)

                if allLeft {
                    log("🧹 Deleting messages then room…")
                    deleteMessagesThenRoom(roomRef: roomRef) { err in
                        if let err = err { log("🔥 deleteMessagesThenRoom error: \(err.localizedDescription)") }
                        else { log("✅ room fully deleted (from list): \(roomId)") }
                    }
                } else {
                    log("↩️ Not deletable yet.")
                }
            }
        }

        }
    }

    // ✅ 단순 로그 유틸 (파일/라인+시간 포함 필요 시 확장 가능)
    private func log(_ s: String,
                     file: String = #fileID, line: Int = #line) {
        print("📒[ChatListView] \(s) (\(file):\(line))")
    }


    
    // 🔧 메시지 먼저 지우고 방 삭제(100개씩 반복)
    private func deleteMessagesThenRoom(roomRef: DocumentReference, completion: @escaping (Error?) -> Void) {
        roomRef.collection("messages").order(by: "timestamp").limit(to: 100)
            .getDocuments { snap, err in
                if let err = err { completion(err); return }
                guard let docs = snap?.documents, !docs.isEmpty else {
                    roomRef.delete(completion: completion)
                    return
                }
                let batch = roomRef.firestore.batch()
                docs.forEach { batch.deleteDocument($0.reference) }
                batch.commit { e in
                    if let e = e { completion(e); return }
                    deleteMessagesThenRoom(roomRef: roomRef, completion: completion)
                }
            }
    }







// MARK: - 수동 파싱용 모델

struct ChatRoomLite {
    let id: String
    let participants: [String]
    let lastMessage: String?
    let lastTimestamp: Timestamp?
    let lastTimestampServer: Timestamp?   // ✅ 추가
    let createdAt: Timestamp?
    let leftAt: [String: Timestamp]
    let unread: [String: Int]
    let typing: [String: Bool]

    init?(doc: QueryDocumentSnapshot) {
        let data = doc.data()
        guard let participants = data["participants"] as? [String] else { return nil }
        self.id = doc.documentID
        self.participants = participants
        self.lastMessage = data["lastMessage"] as? String
        self.lastTimestamp = data["lastTimestamp"] as? Timestamp
        self.lastTimestampServer = data["lastTimestampServer"] as? Timestamp   // ✅
        self.createdAt = data["createdAt"] as? Timestamp

        // leftAt
        if let raw = data["leftAt"] as? [String: Any] {
            var map: [String: Timestamp] = [:]
            for (k, v) in raw {
                if let ts = v as? Timestamp { map[k] = ts }
                else if let mv = v as? [String: Any],
                        let sec = mv["seconds"] as? Int64 {
                    map[k] = Timestamp(seconds: sec, nanoseconds: 0)
                }
            }
            self.leftAt = map
        } else {
            self.leftAt = [:]
        }

        // unread ✅ 반드시 초기화 필요
        if let raw = data["unread"] as? [String: Any] {
            var m: [String: Int] = [:]
            for (k, v) in raw {
                if let n = v as? Int { m[k] = n }
                else if let d = v as? Double { m[k] = Int(d) }
            }
            self.unread = m
        } else {
            self.unread = [:]
        }

        // typing
        if let raw = data["typing"] as? [String: Any] {
            var t: [String: Bool] = [:]
            for (k, v) in raw {
                if let b = v as? Bool { t[k] = b }
            }
            self.typing = t
        } else {
            self.typing = [:]
        }
    }
}




struct ChatListRow: Identifiable {
    let id: String
    let roomId: String
    let otherUid: String
    let otherNickname: String
    let otherPhotoURL: String?
    let lastMessage: String?
    let lastTimestamp: Timestamp?
    let unreadCount: Int                // ✅ 추가
    let isOtherTyping: Bool
}


struct UserProfileLight: Identifiable {
    let id: String
    let nickname: String
    let photoURL: String?
}


