import SwiftUI

struct IntroSplashView: View {
    @EnvironmentObject var appState: AppState

    // MARK: - Drop (물방울)
    @State private var dropOffset: CGFloat = -260
    @State private var dropScale: CGFloat = 0.6
    @State private var dropBlur: CGFloat = 6
    @State private var dropOpacity: Double = 1.0

    // MARK: - Ripple (물결 2겹)
    @State private var showRipple1 = false
    @State private var showRipple2 = false
    @State private var ripple1Scale: CGFloat = 0.2
    @State private var ripple2Scale: CGFloat = 0.2
    @State private var ripple1Opacity: Double = 0.7
    @State private var ripple2Opacity: Double = 0.55

    // MARK: - Logo
    @State private var logoScale: CGFloat = 0.86
    @State private var logoOpacity: Double = 0.0
    @State private var glow = false   // ✨ 글로우 애니메이션

    private let appLogoName = "AppLogo"

    var body: some View {
        ZStack {
            GradientBackground()

            VStack {
                Spacer()

                ZStack {
                    // Ripple
                    Group {
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 2)
                            .frame(width: 220, height: 220)
                            .scaleEffect(ripple1Scale)
                            .opacity(showRipple1 ? ripple1Opacity : 0)
                            .compositingGroup()
                            .blendMode(.screen)
                            .animation(.easeOut(duration: 0.65), value: showRipple1)
                            .animation(.easeOut(duration: 0.85), value: ripple1Scale)

                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 2)
                            .frame(width: 280, height: 280)
                            .scaleEffect(ripple2Scale)
                            .opacity(showRipple2 ? ripple2Opacity : 0)
                            .compositingGroup()
                            .blendMode(.screen)
                            .animation(.easeOut(duration: 0.8), value: showRipple2)
                            .animation(.easeOut(duration: 1.0), value: ripple2Scale)
                    }
                    .drawingGroup()

                    // Drop (물방울)
                    Circle()
                        .fill(LinearGradient(colors: [AppTheme.purple, AppTheme.blue],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)
                        .scaleEffect(x: 1.06, y: 1.0)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 20, height: 20)
                                .offset(x: -10, y: -12)
                        )
                        .scaleEffect(dropScale)
                        .offset(y: dropOffset)
                        .blur(radius: dropBlur)
                        .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 8)
                        .opacity(dropOpacity)

                    // ✅ 최신 톤 아이콘 카드 + 글로우 링
                    AppIconCard(logoName: appLogoName, cardSize: 124, logoSize: 82, corner: 24, glow: glow)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .accessibilityLabel("WonderMinute App Icon")
                }
                .frame(height: 320)

                Spacer()
            }
        }
        .onAppear { runAnimation() }
    }

    // MARK: - Animation
    private func runAnimation() {
        // 1) 물방울 낙하
        withAnimation(.interactiveSpring(response: 0.55, dampingFraction: 0.72, blendDuration: 0.12)) {
            dropOffset = 0
            dropScale = 1.0
            dropBlur = 0
        }

        // 2) 충돌 후 리플 + 로고 등장
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            // ripple 1
            showRipple1 = true
            ripple1Scale = 1.15
            ripple1Opacity = 0.0

            // 물방울 페이드아웃
            withAnimation(.easeOut(duration: 0.25)) {
                dropOpacity = 0.0
                dropScale = 0.92
            }

            // ripple 2 (약간 딜레이)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                showRipple2 = true
                ripple2Scale = 1.25
                ripple2Opacity = 0.0
            }

            // 로고 페이드 + 바운스 + 글로우 시작
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                logoOpacity = 1.0
                logoScale = 1.0
            }
            glow = true
        }

        // 3) 전환: Welcome으로
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.25)) {
                appState.setView(.welcome, reason: "splash finished")
            }
        }
    }
}

// 재사용 가능한 아이콘 카드 컴포넌트 (흰 배경 네모 + 얇은 스트로크 + 글로우 링)
struct AppIconCard: View {
    let logoName: String
    let cardSize: CGFloat
    let logoSize: CGFloat
    let corner: CGFloat
    var glow: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white)
                .frame(width: cardSize, height: cardSize)
                .shadow(color: .black.opacity(0.18), radius: 14, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                )

            Image(logoName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)

            // 은은한 글로우 링
            RoundedRectangle(cornerRadius: corner + 4, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.7), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 4
                )
                .frame(width: cardSize + 20, height: cardSize + 20)
                .blur(radius: 6)
                .opacity(glow ? 0.9 : 0.4)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glow)
        }
    }
}
