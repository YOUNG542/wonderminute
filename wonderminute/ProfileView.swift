import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            // 🌈 그라데이션 배경
            LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                Text("프로필 설정")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("나의 정보를 확인하거나 수정할 수 있어요")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)

                Spacer()

                // 🔴 로그아웃 버튼
                Button(action: {
                    handleLogout()
                }) {
                    Text("로그아웃")
                        .foregroundColor(.red)
                        .bold()
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 5)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
        }
    }

    private func handleLogout() {
        appState.logout()
    }

}
