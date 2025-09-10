import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    // 등장 애니메이션
    @State private var appearLogo = false
    @State private var appearTitle = false
    @State private var appearCTA = false
    @State private var glow = false

    private struct WarmTheme {
        static let bgTop      = Color(red: 1.00, green: 0.98, blue: 0.96)
        static let bgBottom   = Color(red: 1.00, green: 0.96, blue: 0.93)
        static let textMain   = Color(red: 0.24, green: 0.20, blue: 0.19)
        static let textSub    = Color(red: 0.48, green: 0.43, blue: 0.42)
    }

    var body: some View {
        ZStack {
            // 기존 GradientBackground() → 아이보리 계열 그라데이션
            LinearGradient(colors: [WarmTheme.bgTop, WarmTheme.bgBottom],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 40)

                // 최신 톤 아이콘 카드
                AppIconCard(logoName: "AppLogo", cardSize: 124, logoSize: 82, corner: 24, glow: glow)
                    .opacity(appearLogo ? 1 : 0)
                    .scaleEffect(appearLogo ? 1 : 0.94)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appearLogo)

                // 카피 계층
                VStack(spacing: 12) {
                    Text("웜보이스는 당신을 위해 만들어졌어요.")
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundColor(WarmTheme.textMain)
                        .multilineTextAlignment(.center)
                        .kerning(-0.5)
                        .padding(.horizontal, 28)
                        .opacity(appearTitle ? 1 : 0)
                        .offset(y: appearTitle ? 0 : 8)
                        .animation(.easeOut(duration: 0.28).delay(0.05), value: appearTitle)

                    Text("지금 느끼는 감정을 글로 남겨보세요.\n단 하나의 순간을 경험하세요.")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(WarmTheme.textSub)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 32)
                        .opacity(appearTitle ? 0.9 : 0)
                        .offset(y: appearTitle ? 0 : 8)
                        .animation(.easeOut(duration: 0.28).delay(0.12), value: appearTitle)
                }

                Spacer()

                // CTA: 버튼 스타일은 아래에서 교체
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
                .buttonStyle(WMSolidPrimaryButtonStyle_Warm()) // ← 따뜻한 버튼 스타일
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


// 따뜻한 메인 버튼 스타일 (핑크 → 피치 그라데이션)
struct WMSolidPrimaryButtonStyle_Warm: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.65, blue: 0.66), // 살짝 진한 핑크
                        Color(red: 1.00, green: 0.78, blue: 0.60)  // 피치
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.10 : 0.16),
                    radius: configuration.isPressed ? 6 : 12, y: configuration.isPressed ? 2 : 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

