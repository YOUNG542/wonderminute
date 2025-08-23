import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    // 등장 애니메이션
    @State private var appearLogo = false
    @State private var appearTitle = false
    @State private var appearCTA = false
    @State private var glow = false

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 24) {
                Spacer(minLength: 40)

                // ✅ 최신 톤 아이콘 카드
                AppIconCard(logoName: "AppLogo", cardSize: 124, logoSize: 82, corner: 24, glow: glow)
                    .opacity(appearLogo ? 1 : 0)
                    .scaleEffect(appearLogo ? 1 : 0.94)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appearLogo)

                // ✅ 카피 계층
                VStack(spacing: 12) {
                    Text("원더미닛에 오신 걸 환영합니다!")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundColor(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .kerning(-0.5)
                        .padding(.horizontal, 28)
                        .opacity(appearTitle ? 1 : 0)
                        .offset(y: appearTitle ? 0 : 8)
                        .animation(.easeOut(duration: 0.28).delay(0.05), value: appearTitle)

                    Text("1:1 감성 통화로 연결되는\n단 하나의 순간을 경험하세요.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .opacity(appearTitle ? 0.9 : 0)
                        .offset(y: appearTitle ? 0 : 8)
                        .animation(.easeOut(duration: 0.28).delay(0.12), value: appearTitle)
                }

                Spacer()

                // ✅ CTA: 솔리드 버튼
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appState.setView(.intro, reason: "welcome tapped start")
                    }
                } label: {
                    Text("시작하기")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(WMSolidPrimaryButtonStyle())
                .padding(.horizontal, 24)
                .opacity(appearCTA ? 1 : 0)
                .offset(y: appearCTA ? 0 : 8)
                .animation(.easeOut(duration: 0.28).delay(0.18), value: appearCTA)

                Spacer(minLength: 34)
            }
        }
        .onAppear {
            appearLogo = true
            appearTitle = true
            appearCTA = true
            glow = true
        }
    }
}

// 버튼 스타일은 기존 그대로 사용
struct WMSolidPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                LinearGradient(colors: [AppTheme.purple, AppTheme.blue],
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(configuration.isPressed ? 0.10 : 0.18),
                    radius: configuration.isPressed ? 6 : 12, y: configuration.isPressed ? 2 : 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
            )
    }
}
