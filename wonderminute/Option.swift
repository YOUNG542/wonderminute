import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

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
                Section(header: Text("계정")) {
                    NavigationLink("프로필 미리보기") { ProfilePreviewStub() }
                }
                
                Section(header: Text("알림")) {
                    Toggle("푸시 알림", isOn: $notifyOn)
                    Toggle("마케팅 동의", isOn: $marketingOn)
                }
                
                Section(header: Text("고객센터")) {
                    NavigationLink("도움말 / 문의") { HelpStub() }
                }
                
                Section(header: Text("약관")) {
                    NavigationLink("오픈소스 라이선스") { LicensesStub() }
                }
                
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
                // 최종 확인으로 한 단계 더
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
    
    // MARK: - 계정 삭제 로직
    private func deleteAccount() async {
        guard let user = Auth.auth().currentUser else { errorMessage = "로그인 상태가 아닙니다."; return }
        let uid = user.uid
        let db = Firestore.firestore()
        let storage = Storage.storage()
        
        await MainActor.run { isWorking = true }
        do {
            // 0) 프로필 URL 읽기 (있으면 이후 삭제에 사용)
            let userDoc = try await db.collection("users").document(uid).getDocument(source: .server)
            let urlString = userDoc.data()?["profileImageUrl"] as? String
            
            // 1) Firestore 문서 삭제
            try await db.collection("users").document(uid).delete()
            
            // 2) Storage 파일 삭제 (URL 기준)
            if let urlString, let ref = try? storage.reference(forURL: urlString) {
                try? await ref.delete()
            }
            
            // 3) Auth 유저 삭제
            try await user.delete()
            
            await MainActor.run {
                isWorking = false
                appState.logout()
            }
        } catch {
            let ns = error as NSError
            if ns.code == AuthErrorCode.requiresRecentLogin.rawValue {
                do {
                    // ✅ 재인증 (애플 or 카카오 커스텀 토큰 자동 선택)
                    try await AuthManager.shared.reauthenticateUser()
                    try await Auth.auth().currentUser?.delete()
                    await MainActor.run {
                        isWorking = false
                        appState.logout()
                    }
                } catch {
                    await MainActor.run {
                        isWorking = false
                        errorMessage = "재인증 또는 삭제에 실패했습니다: \(error.localizedDescription)"
                    }
                }
            } else {
                await MainActor.run {
                    isWorking = false
                    errorMessage = "계정 삭제에 실패했습니다: \(ns.localizedDescription)"
                }
            }
        }
    }
    
    
    
    // MARK: - 임시 화면들
    private struct ProfilePreviewStub: View {
        var body: some View {
            ZStack {
                GradientBackground().ignoresSafeArea()
                Text("프로필 미리보기 (추후 구현)")
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private struct HelpStub: View {
        var body: some View {
            ZStack {
                GradientBackground().ignoresSafeArea()
                Text("도움말 / 문의 (추후 구현)")
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private struct LicensesStub: View {
        var body: some View {
            ZStack {
                GradientBackground().ignoresSafeArea()
                Text("오픈소스 라이선스 (추후 구현)")
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
