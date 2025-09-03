import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct ReportedUsersMonitorView: View {
    // MARK: - Tabs
    enum Tab: String, CaseIterable {
        case queue = "대기"
        case reviewing = "검토중"
        case actioned = "조치완료"
        case dismissed = "보류/기각"

        var triageKey: String {
            switch self {
            case .queue: return "queued"
            case .reviewing: return "reviewing"
            case .actioned: return "actioned"
            case .dismissed: return "dismissed"
            }
        }
    }

    // MARK: - Local Model
    struct Report: Identifiable {
        let id: String
        let reporterUid: String
        let reportedUid: String
        let type: String           // "폭언/혐오", "성적", ...
        let subtype: String
        let description: String
        let createdAt: Date?
        let triageStatus: String   // queued/reviewing/actioned/dismissed
        let attachments: [String]
        let roomId: String?
        let timestampInCall: Int?
    }

    // MARK: - State
    @State private var selectedTab: Tab = .queue
    @State private var searchText: String = ""
    @State private var selectedType: String = "전체" // 폭언/혐오, 성적, 사기, 스팸, 미성년, 기타…
    @State private var onlyRepeatOffenders = false

    @State private var reports: [Report] = []
    @State private var listener: ListenerRegistration?
    
    
    private let db = Firestore.firestore()

    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            VStack(spacing: 12) {
                // 상단 필터
                filterBar

                // 탭
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // 리스트 (Firestore 실데이터)
                List {
                    Section(header: Text("\(selectedTab.rawValue) · 최근 신고")) {
                        let rows = filteredReports
                        if rows.isEmpty {
                            Text("데이터가 없습니다.").foregroundStyle(.secondary)
                        } else {
                            ForEach(rows) { r in
                                NavigationLink {
                                    ReportCaseDetailView(reportId: r.id) // TODO: 실제 상세로 연결 시 r 전달
                                } label: {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color.orange.opacity(0.2))
                                            .frame(width: 36, height: 36)
                                            .overlay(Text("R").font(.footnote.bold()))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(r.reportedUid.isEmpty ? "(unknown)" : r.reportedUid)
                                                .font(.subheadline).bold()
                                            Text("유형: \(r.type)\(repeatSuffix(for: r.reportedUid))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(statusBadgeText(for: r.triageStatus))
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(statusBadgeColor(for: r.triageStatus).opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("신고 모니터링")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    // MARK: - Firestore
    private func startListening(limit: Int = 500) {
        guard listener == nil else { return }
        listener = db.collection("reports")
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .addSnapshotListener { snap, err in
                guard let docs = snap?.documents else {
                    reports = []
                    return
                }
                reports = docs.compactMap { parseReport($0) }
            }
    }

    private func stopListening() {
        listener?.remove()
        listener = nil
    }

    private func parseReport(_ d: DocumentSnapshot) -> Report? {
        let data = d.data() ?? [:]

        let reporterUid = data["reporterUid"] as? String ?? ""
        let reportedUid = data["reportedUid"] as? String ?? ""
        let type = data["type"] as? String ?? ""
        let subtype = data["subtype"] as? String ?? ""
        let description = data["description"] as? String ?? ""
        let attachments = data["attachments"] as? [String] ?? []

        var triageStatus = "queued"
        if let triage = data["triage"] as? [String: Any],
           let s = triage["status"] as? String {
            triageStatus = s
        }

        var roomId: String? = nil
        var tsInCall: Int? = nil
        if let ctx = data["context"] as? [String: Any] {
            roomId = ctx["roomId"] as? String
            tsInCall = ctx["timestampInCall"] as? Int
        }

        let createdAt: Date?
        if let ts = data["createdAt"] as? Timestamp {
            createdAt = ts.dateValue()
        } else {
            createdAt = nil
        }

        return Report(
            id: d.documentID,
            reporterUid: reporterUid,
            reportedUid: reportedUid,
            type: type,
            subtype: subtype,
            description: description,
            createdAt: createdAt,
            triageStatus: triageStatus,
            attachments: attachments,
            roomId: roomId,
            timestampInCall: tsInCall
        )
    }

    // MARK: - Filters / Derived
    private var filteredReports: [Report] {
        var arr = reports.filter { $0.triageStatus == selectedTab.triageKey }

        if selectedType != "전체" {
            arr = arr.filter { $0.type == selectedType }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            arr = arr.filter {
                $0.reportedUid.lowercased().contains(q) ||
                $0.reporterUid.lowercased().contains(q) ||
                $0.subtype.lowercased().contains(q) ||
                $0.description.lowercased().contains(q)
            }
        }

        if onlyRepeatOffenders {
            let counts = countsByReportedUid()
            arr = arr.filter { (counts[$0.reportedUid] ?? 0) >= 2 }
        }

        return arr
    }

    private func countsByReportedUid() -> [String: Int] {
        var dict: [String: Int] = [:]
        for r in reports {
            dict[r.reportedUid, default: 0] += 1
        }
        return dict
    }

    private func repeatSuffix(for uid: String) -> String {
        let c = countsByReportedUid()[uid] ?? 1
        return c >= 2 ? "  • 누적 \(c)건" : ""
    }

    // MARK: - UI helpers
    private func statusBadgeText(for s: String) -> String {
        switch s {
        case "queued": return "큐 대기"
        case "reviewing": return "검토중"
        case "actioned": return "조치완료"
        case "dismissed": return "보류/기각"
        default: return s
        }
    }

    private func statusBadgeColor(for s: String) -> Color {
        switch s {
        case "queued": return .yellow
        case "reviewing": return .blue
        case "actioned": return .green
        case "dismissed": return .gray
        default: return .secondary
        }
    }

    // MARK: - Filter bar
    private var filterBar: some View {
        HStack(spacing: 8) {
            TextField("UID/닉네임/메모 검색", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Menu(selectedType) {
                Button("전체") { selectedType = "전체" }
                Button("폭언/혐오") { selectedType = "폭언/혐오" }
                Button("성적") { selectedType = "성적" }
                Button("불법/사기") { selectedType = "불법/사기" }
                Button("스팸/광고") { selectedType = "스팸/광고" }
                Button("미성년 의심") { selectedType = "미성년 의심" }
                Button("기타") { selectedType = "기타" }
            }
            .buttonStyle(.borderedProminent)

            Toggle("상습만", isOn: $onlyRepeatOffenders)
                .toggleStyle(.switch)
        }
        .padding(.horizontal)
    }
}

// 기존 플레이스홀더는 그대로 두되, 나중에 실제 상세 뷰로 교체
private struct ReportCaseDetailPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("신고 상세 (샘플)")
                        .font(.title3.bold())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("신고된 UID: reportedUid_xxx")
                            Text("누적 신고: 5건 / 최근 7일 3건")
                            Text("최근 사유: 폭언/혐오")
                            Text("증거자료: 통화 로그/채팅 일부 (추후 표시)")
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("운영 메모").font(.headline)
                            Text("— 여기에 운영자 메모/조치 이력 표시 예정")
                                .foregroundStyle(.secondary)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("가능한 조치").font(.headline)
                            Text("• 경고 푸시/팝업\n• 일시 차단(매칭 제한)\n• 영구 정지\n• 보류/기각")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("신고 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ReportCaseDetailView: View {
    let reportId: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var report: ReportedDoc? = nil
    @State private var sameUserReports: [ReportedDoc] = []
    @State private var loading = false
    @State private var errMsg: String?
    @State private var applying = false
    @State private var showViewer = false          // ⬅️ 전체화면 뷰어 표시
    @State private var viewerStartIndex = 0        // ⬅️ 시작 인덱스
    private let db = Firestore.firestore()
    private var docRef: DocumentReference { db.collection("reports").document(reportId) }
    
    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("신고 상세")
                        .font(.title3.bold())
                    
                    if let r = report {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text("상태"); Spacer(); StatusBadge(r.triageStatus) }
                                RowKV("생성 시각", r.createdAt.map { shortDate($0) } ?? "—")
                                RowKV("신고자 UID", r.reporterUid.isEmpty ? "—" : r.reporterUid)
                                RowKV("피신고자 UID", r.reportedUid.isEmpty ? "—" : r.reportedUid)
                                RowKV("유형", r.type.isEmpty ? "—" : r.type)
                                if !r.subtype.isEmpty { RowKV("세부유형", r.subtype) }
                                if let room = r.roomId { RowKV("룸 ID", room) }
                                if let t = r.timestampInCall { RowKV("통화 내 타임스탬프", "\(t)초") }
                            }
                        }
                        
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("설명").font(.headline)
                                Text(r.description.isEmpty ? "—" : r.description)
                            }
                        }
                        
                        if !r.attachments.isEmpty {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("첨부").font(.headline)
                                    
                                    // 가로 썸네일 스크롤
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 10) {
                                            ForEach(Array(r.attachments.enumerated()), id: \.offset) { idx, s in
                                                if let u = URL(string: s) {
                                                    AsyncImage(url: u) { phase in
                                                        switch phase {
                                                        case .success(let image):
                                                            image
                                                                .resizable()
                                                                .scaledToFill()
                                                                .frame(width: 90, height: 90)
                                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
                                                                .onTapGesture {
                                                                    viewerStartIndex = idx
                                                                    showViewer = true
                                                                }
                                                        case .failure(_):
                                                            fallbackThumb
                                                        case .empty:
                                                            ProgressView()
                                                                .frame(width: 90, height: 90)
                                                        @unknown default:
                                                            fallbackThumb
                                                        }
                                                    }
                                                } else {
                                                    fallbackThumb
                                                }
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                            }
                            // 전체화면 뷰어
                            .fullScreenCover(isPresented: $showViewer) {
                                AttachmentViewer(urlStrings: r.attachments, startIndex: viewerStartIndex) {
                                    showViewer = false
                                }
                            }
                        }
                        
                        
                        // 피신고자 누적 신고 히스토리
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("피신고자 신고 히스토리").font(.headline)
                                if sameUserReports.isEmpty {
                                    Text("기록 없음").foregroundStyle(.secondary)
                                } else {
                                    ForEach(sameUserReports.prefix(10)) { x in
                                        HStack {
                                            StatusBadge(x.triageStatus)
                                            Text("\(shortDate(x.createdAt ?? Date()))  ·  \(x.type)")
                                                .font(.caption)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 상태 전환 액션
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("상태 변경")
                                    .font(.headline)
                                StatusButtons(current: r.triageStatus) { newStatus in
                                    updateStatus(newStatus)
                                }
                            }
                            .foregroundStyle(.primary) // ← 텍스트를 시스템 기본색으로 강제 (흰 배경 위에서 검정)
                        }
                        .background(.ultraThinMaterial) // ← 섹션 카드 밝은 배경
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        
                        
                        
                        // 제재 액션
                        // 제재 액션
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("제재 적용(피신고자)")
                                    .font(.headline)
                                Text("매칭/메시지/통화 전면 제한을 가정한 샘플 로직. 서버 권위가 있다면 Functions로 이동 권장.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                if applying { ProgressView().padding(.vertical, 4) }
                                
                                HStack {
                                    Button("3일 정지") { applySuspension(days: 3) }
                                    Button("7일 정지") { applySuspension(days: 7) }
                                    Button("1달 정지") { applySuspension(days: 30) }
                                    Button("영구 정지") { applySuspension(days: nil) }
                                    Divider().frame(height: 20)
                                    Button("정지 해제") { liftSuspension() }            // ← 추가
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(applying)
                            }
                            .foregroundStyle(.primary)
                        }
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        
                        
                    }
                    
                    if let e = errMsg {
                        Text(e).foregroundColor(.red)
                    }
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("조치") {
                        Button("대기로") { updateStatus("queued") }
                        Button("검토중으로") { updateStatus("reviewing") }
                        Button("조치완료로") { updateStatus("actioned") }
                        Button("보류/기각으로") { updateStatus("dismissed") }
                        Divider()
                        Button("닫기") { dismiss() }
                    }
                }
            }
        }
        .navigationTitle("신고 상세")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { load() }
    }
    
    // MARK: - Data Types
    struct ReportedDoc: Identifiable {
        let id: String
        let reporterUid: String
        let reportedUid: String
        let type: String
        let subtype: String
        let description: String
        let createdAt: Date?
        let triageStatus: String
        let attachments: [String]
        let roomId: String?
        let timestampInCall: Int?
    }
    
    // MARK: - Load
    private func load() {
        loading = true
        errMsg = nil
        docRef.addSnapshotListener { snap, err in
            if let err { self.errMsg = "로드 실패: \(err.localizedDescription)"; return }
            guard let d = snap, let r = parse(d) else { return }
            self.report = r
            self.fetchSameUserReports(for: r.reportedUid)
        }
    }
    
    private func fetchSameUserReports(for reportedUid: String) {
        guard !reportedUid.isEmpty else { sameUserReports = []; return }
        db.collection("reports")
            .whereField("reportedUid", isEqualTo: reportedUid)
            .order(by: "createdAt", descending: true)
            .limit(to: 50)
            .getDocuments { snap, err in
                if let docs = snap?.documents {
                    self.sameUserReports = docs.compactMap(parse)
                } else {
                    self.sameUserReports = []
                }
            }
    }
    
    private func parse(_ d: DocumentSnapshot) -> ReportedDoc? {
        let data = d.data() ?? [:]
        let reporterUid = data["reporterUid"] as? String ?? ""
        let reportedUid = data["reportedUid"] as? String ?? ""
        let type = data["type"] as? String ?? ""
        let subtype = data["subtype"] as? String ?? ""
        let description = data["description"] as? String ?? ""
        let attachments = data["attachments"] as? [String] ?? []
        let triageStatus: String = {
            if let triage = data["triage"] as? [String: Any],
               let s = triage["status"] as? String {
                return s
            }
            return "queued"
        }()
        
        var roomId: String? = nil
        var tsInCall: Int? = nil
        if let ctx = data["context"] as? [String: Any] {
            roomId = ctx["roomId"] as? String
            tsInCall = ctx["timestampInCall"] as? Int
        }
        
        let createdAt: Date? = (data["createdAt"] as? Timestamp)?.dateValue()
        
        return ReportedDoc(
            id: d.documentID,
            reporterUid: reporterUid,
            reportedUid: reportedUid,
            type: type,
            subtype: subtype,
            description: description,
            createdAt: createdAt,
            triageStatus: triageStatus,
            attachments: attachments,
            roomId: roomId,
            timestampInCall: tsInCall
        )
    }
    
    // MARK: - Actions: triage.status 업데이트
    private func updateStatus(_ newStatus: String) {
        guard report != nil else { return }
        let now = FieldValue.serverTimestamp()
        docRef.setData([
            "triage": [
                "status": newStatus,
                "updatedAt": now
            ]
        ], merge: true) { err in
            if let err { self.errMsg = "상태 업데이트 실패: \(err.localizedDescription)" }
        }
    }
    
    // MARK: - Actions: 제재 적용 (샘플 Firestore 배치)
    /// days: 3/7/30, nil이면 영구
    private func applySuspension(days: Int?) {
        guard let r = report, !r.reportedUid.isEmpty else { return }
        applying = true; errMsg = nil
        
        let me = Auth.auth().currentUser?.uid ?? "system"
        let batch = db.batch()
        let now = FieldValue.serverTimestamp()
        
        // 1) 제재 기록: moderation/suspensions/{autoId}
        let suspRef = db.collection("moderation").document("suspensions")
            .collection("items").document()
        var payload: [String: Any] = [
            "userUid": r.reportedUid,
            "byUid": me,
            "reason": r.type.isEmpty ? "violation" : r.type,
            "sourceReportId": r.id,
            "createdAt": now,
            "scope": ["match","message","call"],
        ]

        if let days {
            payload["durationDays"] = days
            payload["expiresAt"] = Timestamp(date: Date().addingTimeInterval(Double(days) * 86400))
            payload["permanent"] = false
        } else {
            // ❗️delete() 쓰지 말고 그냥 필드를 빼둔다
            payload["permanent"] = true
        }

        batch.setData(payload, forDocument: suspRef) // 그대로 OK

        
        // 2) 사용자 플래그: users/{uid} (클라이언트 가드/서버 가드에서 참고)
        let userRef = db.collection("users").document(r.reportedUid)
        var userPatch: [String: Any] = [
            "moderation": [
                "suspended": true,
                "updatedAt": now,
                "scope": ["match","message","call"]
            ]
        ]
        if let days {
            userPatch["moderation"] = [
                "suspended": true,
                "updatedAt": now,
                "scope": ["match","message","call"],
                "suspendedUntil": Timestamp(date: Date().addingTimeInterval(Double(days) * 86400))
            ]
        } else {
            userPatch["moderation"] = [
                "suspended": true,
                "updatedAt": now,
                "scope": ["match","message","call"],
                "permanentBan": true
            ]
        }
        batch.setData(userPatch, forDocument: userRef, merge: true)
        
        // 3) 매칭 큐에서도 제외(선택)
        let queueRef = db.collection("matchingQueue").document(r.reportedUid)
        batch.setData([
            "blockedByModeration": true,
            "updatedAt": now
        ], forDocument: queueRef, merge: true)
        
        // 4) 현재 신고의 triage 상태를 actioned로
        let reportRef = docRef
        batch.setData([
            "triage": [
                "status": "actioned",
                "updatedAt": now
            ]
        ], forDocument: reportRef, merge: true)
        
        batch.commit { err in
            applying = false
            if let err {
                self.errMsg = "제재 적용 실패: \(err.localizedDescription)"
            }
        }
    }
    
    // MARK: - Actions: 정지 해제
    private func liftSuspension() {
        guard let r = report, !r.reportedUid.isEmpty else { return }
        applying = true; errMsg = nil
        
        let me  = Auth.auth().currentUser?.uid ?? "system"
        let now = FieldValue.serverTimestamp()
        let batch = db.batch()
        
        // 1) 해제 로그 남기기 (감사용)
        let logRef = db.collection("moderation").document("suspensions")
            .collection("items").document()
        let logPayload: [String: Any] = [
            "userUid": r.reportedUid,
            "byUid": me,
            "action": "revoke",
            "sourceReportId": r.id,
            "createdAt": now
        ]
        batch.setData(logPayload, forDocument: logRef)
        
        // 2) 사용자 moderation 상태 해제
        let userRef = db.collection("users").document(r.reportedUid)
        batch.setData([
            "moderation": [
                "suspended": false,
                "updatedAt": now,
                "scope": [],
                "suspendedUntil": FieldValue.delete(),
                "permanentBan": FieldValue.delete()
            ]
        ], forDocument: userRef, merge: true)
        
        // 3) 매칭 큐 차단 해제(있다면)
        let queueRef = db.collection("matchingQueue").document(r.reportedUid)
        batch.setData([
            "blockedByModeration": false,
            "updatedAt": now
        ], forDocument: queueRef, merge: true)
        
        batch.commit { err in
            applying = false
            if let err {
                self.errMsg = "정지 해제 실패: \(err.localizedDescription)"
            }
        }
    }
    
    
    // MARK: - UI helpers
    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: d)
    }
    
    private func RowKV(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
            Spacer()
            Text(v).foregroundStyle(.secondary)
        }
    }
    
    private func StatusBadge(_ status: String) -> some View {
        Text(badgeText(status))
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(badgeColor(status).opacity(0.2))
            .clipShape(Capsule())
    }
    
    private func badgeText(_ s: String) -> String {
        switch s {
        case "queued": return "대기"
        case "reviewing": return "검토중"
        case "actioned": return "조치완료"
        case "dismissed": return "보류/기각"
        default: return s
        }
    }
    
    private func badgeColor(_ s: String) -> Color {
        switch s {
        case "queued": return .yellow
        case "reviewing": return .blue
        case "actioned": return .green
        case "dismissed": return .gray
        default: return .secondary
        }
    }
    private var fallbackThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.1))
            Image(systemName: "photo")
                .imageScale(.large)
                .foregroundStyle(.secondary)
        }
        .frame(width: 90, height: 90)
    }

    
}

// 신고 상세 화면 하단에 추가 (같은 파일 안)
private struct StatusButtons: View {
    let current: String                  // "queued" | "reviewing" | "actioned" | "dismissed"
    let onChange: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("대기로")       { onChange("queued") }
                    .buttonStyle(.bordered)
                    .disabled(current == "queued")

                Button("검토중으로")   { onChange("reviewing") }
                    .buttonStyle(.borderedProminent)
                    .disabled(current == "reviewing")
            }

            HStack {
                Button("조치완료로")   { onChange("actioned") }
                    .buttonStyle(.bordered)
                    .disabled(current == "actioned")

                Button("보류/기각으로") { onChange("dismissed") }
                    .buttonStyle(.bordered)
                    .disabled(current == "dismissed")
            }
        }
    }
}

// 전체화면 첨부 뷰어 (좌우 스와이프 + 핀치 줌 + 더블탭 줌)
private struct AttachmentViewer: View {
    let urlStrings: [String]
    let startIndex: Int
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(urlStrings: [String], startIndex: Int, onClose: @escaping () -> Void) {
        self.urlStrings = urlStrings
        self.startIndex = startIndex
        self.onClose = onClose
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(urlStrings.enumerated()), id: \.offset) { i, s in
                    if let u = URL(string: s) {
                        ZoomableAsyncImage(url: u)
                            .tag(i)
                    } else {
                        Image(systemName: "xmark.octagon")
                            .foregroundStyle(.white)
                            .tag(i)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            // 닫기 버튼
            VStack {
                HStack {
                    Button {
                        onClose()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding([.top, .leading], 16)
                    Spacer()
                }
                Spacer()
            }
        }
        .onDisappear { onClose() }
    }
}

private struct ZoomableAsyncImage: View {
    let url: URL
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                        .offset(offset)
                        .scaleEffect(scale)
                        .gesture(magnificationGesture().simultaneously(with: dragGesture()))
                        .gesture(doubleTapGesture(in: geo.size))
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: scale)
                        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: offset)
                case .empty:
                    ProgressView().tint(.white)
                        .frame(width: geo.size.width, height: geo.size.height)
                case .failure(_):
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.white)
                        .frame(width: geo.size.width, height: geo.size.height)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    // 핀치 줌
    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                var newScale = scale * delta
                newScale = min(max(newScale, 1.0), 4.0)
                scale = newScale
                lastScale = value
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale <= 1.01 {
                    scale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    // 드래그로 이동
    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.0 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    // 더블 탭으로 줌 인/아웃
    private func doubleTapGesture(in size: CGSize) -> some Gesture {
        TapGesture(count: 2).onEnded {
            if scale > 1.0 {
                scale = 1.0
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.0
            }
        }
    }
}
