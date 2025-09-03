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
                // MARK: - 고객센터
                Section(header: Text("고객센터")) {
                    NavigationLink("실시간 상담 서비스") { LiveSupportIntroView() }
                }

                
              
                // ✅ 상담자 전용 (권한 있을 때만 섹션 자체를 렌더링)
                if Auth.auth().currentUser?.uid == COUNSELOR_UID {
                    Section(header: Text("상담자 전용")) {
                        NavigationLink("상담 인박스 열기") { CounselorInboxView() }
                        NavigationLink("신고된 유저들 모니터링") { ReportedUsersMonitorView() }
                        // 필요 시 바로 특정 유저와의 채팅으로 들어가고 싶으면 아래 라인을 사용
                        // NavigationLink("상담 채팅 바로가기") { CounselorChatView(userId: "<특정 userId>") }
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
                    NavigationLink("차단했던 사용자 관리") { BlockedUsersView() }
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
        @State private var showUnblockConfirm = false
        @State private var selectedUser: UserRow?
      
        var body: some View {
            ZStack {
                GradientBackground().ignoresSafeArea()
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if isLoading {
                            HStack {
                                Spacer()
                                ProgressView("불러오는 중…").tint(.white)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }

                        if let error {
                            Text(error)
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.vertical, 4)
                        }

                        if rows.isEmpty && !isLoading && error == nil {
                            Text("차단한 사용자가 없습니다.")
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.vertical, 4)
                        }

                        ForEach(rows) { row in
                            Button {
                                selectedUser = row
                                showUnblockConfirm = true
                            } label: {
                                // ⬇️ 유닛 카드 - 기존 HStack 그대로
                                HStack(spacing: 12) {
                                    // 아바타
                                    if let url = row.photoURL, !url.isEmpty, let u = URL(string: url) {
                                        AsyncImage(url: u) { phase in
                                            switch phase {
                                            case .success(let img):
                                                img.resizable()
                                                    .scaledToFill()
                                                    .frame(width: 52, height: 52)
                                                    .clipShape(Circle())
                                                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                                            default:
                                                Circle().fill(Color.white.opacity(0.08))
                                                    .frame(width: 52, height: 52)
                                                    .overlay(Image(systemName: "person.fill")
                                                                .foregroundStyle(.white.opacity(0.6)))
                                            }
                                        }
                                    } else {
                                        Circle().fill(Color.white.opacity(0.08))
                                            .frame(width: 52, height: 52)
                                            .overlay(Image(systemName: "person.fill")
                                                        .foregroundStyle(.white.opacity(0.6)))
                                    }

                                    // 텍스트
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(row.nickname.isEmpty ? "알 수 없음" : row.nickname)
                                            .font(.headline)
                                            .foregroundColor(.black)

                                        Text("탭하여 차단 해제")
                                            .font(.caption)
                                            .foregroundColor(.gray)

                                    }

                                    Spacer()

                                    // 얇은 chevron
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(.gray)

                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.white) // 완전 흰색 배경
                                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                                )

                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 0)
                    .padding(.horizontal, 16)  // 좌우 인셋
                }
                .scrollIndicators(.hidden)
                .alert("차단 해제", isPresented: $showUnblockConfirm) {
                    Button("취소", role: .cancel) { }
                    if let u = selectedUser {
                        Button("해제", role: .destructive) { unblock(u.uid) }
                    }
                } message: {
                    Text("\(selectedUser?.nickname ?? "사용자") 님의 차단을 해제하시겠어요?")
                }

            }
            .navigationTitle("차단했던 사용자")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(.white)
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

            Task {
                do {
                    var tmp: [UserRow] = []
                    for uid in uids {
                        let snap = try await db.collection("users").document(uid).getDocument()
                        let nick  = (snap.get("nickname") as? String) ?? ""
                        let photo = (snap.get("profileImageUrl") as? String)          // ← 사진 URL 함께 로드
                        tmp.append(UserRow(uid: uid, nickname: nick, photoURL: photo))
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
            let photoURL: String?
            var id: String { uid }
        }

    }

}
