import SwiftUI
import FirebaseAuth
import FirebaseFirestore
// import FirebaseFirestoreSwift   // ❌ 제거

struct ChatListView: View {
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

            List {
                // programmatic navigation anchor
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
                } label: { EmptyView() }
                .frame(width: 0, height: 0)
                .hidden()


                Section(header: Text("최근 채팅").font(.headline)) {
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
                                        .foregroundStyle(.white)
                                    Text(r.lastMessage ?? "대화를 시작해 보세요")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
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
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
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
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("채팅")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            subscribe()
        }
        .onDisappear {
            listener?.remove()
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
                        .filter { room in
                            if let myLeft = room.leftAt[myUid], let last = room.lastTimestamp {
                                return last.dateValue() > myLeft.dateValue()
                            }
                            return true
                        }
                        .map { room -> ChatListRow in
                            let other = room.participants.first(where: { $0 != myUid }) ?? ""
                            let p = profiles[other]
                            let unread = room.unread[myUid] ?? 0        // ✅ 미읽음 수
                            return ChatListRow(
                                id: room.id,
                                roomId: room.id,
                                otherUid: other,
                                otherNickname: p?.nickname ?? "(알 수 없음)",
                                otherPhotoURL: p?.photoURL,
                                lastMessage: room.lastMessage,
                                lastTimestamp: room.lastTimestamp,
                                unreadCount: unread                      // ✅ 추가
                            )
                        }

                    self.rows = mapped

                    self.loading = false

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
                        let photo = data["ProfileImageUrl"] as? String
                        result[d.documentID] = UserProfileLight(id: d.documentID, nickname: nick, photoURL: photo)
                    }
                }
        }
        group.notify(queue: .main) { completion(result) }
    }
    
    // ✅ 리스트에서의 나가기: 방 문서에 leftAt.{uid} 기록 (participants 유지)
    // ✅ 리스트에서의 나가기: leftAt 기록 + (둘 다 나간 상태면) 메시지→방 삭제
    private func leaveRoom(roomId: String) {
        guard !myUid.isEmpty else { return }
        let roomRef = db.collection("chatRooms").document(roomId)

        // 1) 내 leave 시각 기록
        roomRef.setData(["leftAt": [myUid: FieldValue.serverTimestamp()]], merge: true) { err in
            if let err = err {
                self.error = "방 나가기 실패: \(err.localizedDescription)"
                return
            }
            // 2) 둘 다 나갔는지 확인 후 삭제
            roomRef.getDocument { snap, e in
                if let e = e { print("leave check error: \(e.localizedDescription)"); return }
                guard let data = snap?.data() else { return }

                let participants = (data["participants"] as? [String]) ?? []
                let lastTs = data["lastTimestamp"] as? Timestamp
                let leftMap = data["leftAt"] as? [String: Any] ?? [:]

                let leftTsForAll: [Timestamp] = participants.compactMap { uid in
                    if let ts = leftMap[uid] as? Timestamp { return ts }
                    if let m = leftMap[uid] as? [String: Any], let sec = m["seconds"] as? Int64 {
                        return Timestamp(seconds: sec, nanoseconds: 0)
                    }
                    return nil
                }

                let allLeft = leftTsForAll.count == participants.count
                let maxLeft = leftTsForAll.max(by: { $0.dateValue() < $1.dateValue() })
                let deletable = allLeft && (lastTs == nil || (maxLeft != nil && lastTs!.dateValue() <= maxLeft!.dateValue()))

                if deletable {
                    deleteMessagesThenRoom(roomRef: roomRef) { err in
                        if let err = err { print("delete room error: \(err.localizedDescription)") }
                    }
                }
            }
        }
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





  
}

// MARK: - 수동 파싱용 모델

struct ChatRoomLite {
    let id: String
    let participants: [String]
    let lastMessage: String?
    let lastTimestamp: Timestamp?
    let createdAt: Timestamp?
    let leftAt: [String: Timestamp]
    let unread: [String: Int]                 // ✅ 추가

    init?(doc: QueryDocumentSnapshot) {
        let data = doc.data()
        guard let participants = data["participants"] as? [String] else { return nil }
        self.id = doc.documentID
        self.participants = participants
        self.lastMessage = data["lastMessage"] as? String
        self.lastTimestamp = data["lastTimestamp"] as? Timestamp
        self.createdAt = data["createdAt"] as? Timestamp

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
}


struct UserProfileLight: Identifiable {
    let id: String
    let nickname: String
    let photoURL: String?
}


