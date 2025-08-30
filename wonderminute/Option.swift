import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseFunctions



struct OptionView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var marketingOn = false
    @State private var notifyOn = true
    
    // 상태
    @State private var showDeleteConfirm = false          // 1차 확인
    @State private var showDeleteConfirmFinal = false     // 2차(최종) 확인
    @State private var isWorking = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()
            
            List {
                // MARK: - 고객센터
                Section(header: Text("고객센터")) {
                    NavigationLink("자주 묻는 질문(FAQ)") { FAQView() }
                    NavigationLink("실시간 상담 서비스") { LiveSupportIntroView() }
                    NavigationLink("질문 게시판") { QABoardStub() }
                }
                
                // ✅ 상담자 전용 진입 버튼 (너 계정일 때만 노출)
                Section(header: Text("상담자 전용")) {
                    if Auth.auth().currentUser?.uid == COUNSELOR_UID {
                        // 인박스 → 개별 채팅으로 이동하는 구조
                        NavigationLink("상담 인박스 열기") { CounselorInboxView() }
                        // 필요 시 바로 특정 유저와의 채팅으로 들어가고 싶으면 아래 라인을 사용
                        // NavigationLink("상담 채팅 바로가기") { CounselorChatView(userId: "<특정 userId>") }
                    } else {
                        Text("권한이 없습니다").foregroundStyle(.secondary)
                    }
                }
                // ✅ 상담자 전용 진입 버튼 (너 계정일 때만 노출)
                Section(header: Text("상담자 전용")) {
                    if Auth.auth().currentUser?.uid == COUNSELOR_UID {
                        NavigationLink("상담 인박스 열기") { CounselorInboxView() }
                        // ⬇️ 추가
                        NavigationLink("신고된 유저들 모니터링") { ReportedUsersMonitorView() }
                    } else {
                        Text("권한이 없습니다").foregroundStyle(.secondary)
                    }
                }

                
                // MARK: - 커뮤니티 & 약관
                Section(header: Text("정책/약관")) {
                    NavigationLink("커뮤니티 가이드라인") { CommunityGuidelinesView() }
                    NavigationLink("이용약관") { TermsOfServiceView() }
                    NavigationLink("개인정보 처리방침") { PrivacyPolicyView() }
                }
                
                // ✅ 차단 관리 진입
                Section(header: Text("안전/차단")) {
                    NavigationLink("차단된 사용자 관리") { BlockedUsersView() }
                }
                // MARK: - 세션
                Section {
                    Button(role: .destructive) {
                        Task { @MainActor in
                            appState.logout()
                            dismiss()
                        }
                    } label: { Text("로그아웃") }
                    
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: { Text("계정 삭제") }
                }
            }
            .onAppear {
                // 로그인 상태일 때 한 번 캐시 로드
                SafetyCenter.shared.loadBlockedUids()
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .navigationTitle("설정")
            .navigationBarTitleDisplayMode(.inline)
            
            if isWorking {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView("처리 중…").tint(.white).controlSize(.large)
            }
        }
        // 1차 확인
        .alert("계정을 정말 삭제할까요?",
               isPresented: $showDeleteConfirm) {
            Button("취소", role: .cancel) { }
            Button("삭제", role: .destructive) {
                showDeleteConfirmFinal = true
            }
        } message: {
            Text("프로필 및 관련 데이터가 모두 제거됩니다.")
        }
        // 2차(최종) 확인
        .alert("정말로 삭제하시겠어요? (최종 확인)",
               isPresented: $showDeleteConfirmFinal) {
            Button("취소", role: .cancel) { }
            Button("네, 삭제합니다", role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("이 작업은 되돌릴 수 없습니다. 계정, 프로필 데이터, 저장된 이미지가 영구 삭제됩니다.")
        }
        // 에러 알림
        .alert("실패", isPresented: Binding(get: { errorMessage != nil },
                                          set: { _ in errorMessage = nil })) {
            Button("확인", role: .cancel) { }
        } message: { Text(errorMessage ?? "") }
    }
    
    // MARK: - 계정 삭제
    private func deleteAccount() async {
        await MainActor.run { isWorking = true }
        defer { Task { @MainActor in isWorking = false } }
        
        do {
            let _ = try await Functions.functions().httpsCallable("deleteSelf").call([:])
            await MainActor.run {
                appState.logout()
                navigateToWelcome()
                dismiss()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "계정 삭제에 실패했습니다: \(error.localizedDescription)"
            }
        }
    }
    
    // 고객센터 - FAQ
    private struct FAQView: View {
        @State private var searchText = ""
        var body: some View {
            ZStack {
                GradientBackground().ignoresSafeArea()
                VStack(spacing: 12) {
                    TextField("검색어를 입력하세요", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                    
                    List {
                        FAQItem(q: "통화는 어떻게 시작하나요?",
                                a: "매칭 후 입장 버튼을 누르면 자동으로 연결됩니다. 연결 전 네트워크 상태를 확인해 주세요.")
                        FAQItem(q: "상대방이 들리지 않아요",
                                a: "마이크 권한/음량을 확인하고, 이어폰/스피커를 바꿔보세요. 그래도 안 되면 앱을 재시작해 주세요.")
                        FAQItem(q: "신고/차단은 어떻게 하나요?",
                                a: "프로필/채팅 화면의 ••• 메뉴에서 신고/차단을 선택할 수 있습니다.")
                        FAQItem(q: "결제 및 환불 규정",
                                a: "초기 30초 유예 후 과금이 시작됩니다. 정책에 따라 환불이 제한될 수 있습니다. (자세한 내용은 ‘이용약관’ 참조)")
                    }
                    .listStyle(.insetGrouped)
                }
                .navigationTitle("FAQ")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        
        private struct FAQItem: View {
            let q: String
            let a: String
            @State private var open = false
            var body: some View {
                DisclosureGroup(isExpanded: $open) {
                    Text(a).font(.subheadline).foregroundStyle(.secondary)
                } label: {
                    Text("Q. \(q)").font(.body)
                }
            }
        }
    }
    
    // 고객센터 - 질문 게시판 (틀)
    private struct QABoardStub: View {
        var body: some View {
            ZStack {
                GradientBackground().ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("질문 게시판 (준비중)")
                        .font(.headline)
                        .padding(.top, 8)
                    List {
                        Text("• 게시판 목록/작성/댓글 기능은 추후 업데이트됩니다.")
                        Text("• 우선 FAQ를 확인해 주세요. 해결되지 않으면 실시간 상담을 이용해주세요.")
                    }
                    .listStyle(.insetGrouped)
                }
                .navigationTitle("질문 게시판")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    
    // 커뮤니티 가이드라인 (틀)
    private struct CommunityGuidelinesView: View {
        var body: some View {
            PolicyScaffold(
                title: "커뮤니티 가이드라인",
                markdown: """
                # 커뮤니티 가이드라인 (초안)
                ...
                """
            )
        }
    }
    
    // 이용약관 (틀)
    private struct TermsOfServiceView: View {
        var body: some View {
            PolicyScaffold(
                title: "이용약관",
                markdown: """
                # 이용약관 (초안)
                ...
                """
            )
        }
    }
    
    // 개인정보 처리방침 (틀)
    private struct PrivacyPolicyView: View {
        var body: some View {
            PolicyScaffold(
                title: "개인정보 처리방침",
                markdown: """
                # 개인정보 처리방침 (초안)
                ...
                """
            )
        }
    }
    
    // 공통 정책 스캐폴드
    private struct PolicyScaffold: View {
        let title: String
        let markdown: String
        var body: some View {
            ZStack {
                GradientBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title).font(.title2).bold().padding(.top, 8)
                        Text(.init(markdown)).font(.callout).tint(.primary).lineSpacing(4)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
    
    @MainActor
    private func navigateToWelcome() {
        appState.goToWelcome(reason: "account deleted")
    }
    private struct BlockedUsersView: View {
        @ObservedObject private var safety = SafetyCenter.shared

        @State private var rows: [UserRow] = []
        @State private var isLoading = true
        @State private var error: String?

        var body: some View {
            List {
                if isLoading { ProgressView("불러오는 중…") }
                if let error { Text(error).foregroundStyle(.red) }

                if rows.isEmpty && !isLoading && error == nil {
                    Text("차단한 사용자가 없습니다.")
                        .foregroundStyle(.secondary)
                }

                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        // 가벼운 아바타(이름 이니셜)
                        Circle().fill(Color.gray.opacity(0.15))
                            .frame(width: 36, height: 36)
                            .overlay(Text(row.initial).font(.headline))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.nickname.isEmpty ? row.uid : row.nickname)
                                .font(.body.weight(.semibold))
                            if !row.nickname.isEmpty {
                                Text(row.uid).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            unblock(row.uid)
                        } label: {
                            Label("차단 해제", systemImage: "person.crop.circle.badge.xmark")
                        }
                    }
                }
            }
            .navigationTitle("차단된 사용자")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: load)
            .refreshable { load() }
        }

        private func load() {
            isLoading = true
            error = nil
            rows.removeAll()

            let uids = Array(safety.blockedUids)
            if uids.isEmpty { isLoading = false; return }

            let db = Firestore.firestore()
            // 닉네임을 살짝 붙여주자 (없으면 UID만 표기)
            Task {
                do {
                    var tmp: [UserRow] = []
                    for uid in uids {
                        let snap = try await db.collection("users").document(uid).getDocument()
                        let nick = (snap.get("nickname") as? String) ?? ""
                        tmp.append(UserRow(uid: uid, nickname: nick))
                    }
                    await MainActor.run {
                        self.rows = tmp.sorted { $0.nickname.lowercased() < $1.nickname.lowercased() }
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.error = "목록을 불러오지 못했어요: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }
        }

        private func unblock(_ uid: String) {
            Task {
                await MainActor.run { isLoading = true }
                SafetyCenter.shared.unblock(uid) { ok in
                    Task { @MainActor in
                        if ok {
                            self.rows.removeAll { $0.uid == uid }
                        } else {
                            self.error = "차단 해제에 실패했어요. 잠시 후 다시 시도해 주세요."
                        }
                        self.isLoading = false
                    }
                }
            }
        }

        struct UserRow: Identifiable {
            let uid: String
            let nickname: String
            var id: String { uid }
            var initial: String { nickname.isEmpty ? "?" : String(nickname.prefix(1)) }
        }
    }

}
