import SwiftUI
import FirebaseAuth

struct IntroAnimationView: View {
    @EnvironmentObject var appState: AppState

    // 등장/모션 상태
    @State private var showLogo = false
    @State private var glow = false
    @State private var showCopy1 = false
    @State private var showCopy2 = false
    @State private var progress: CGFloat = 0
    @State private var canRoute = false

    // 라우팅 취소용
    @State private var workItem: DispatchWorkItem?

    var body: some View {
        ZStack {
            // ✅ 브랜드 무드 배경(이미 구현돼 있음)
            GradientBackground()
                .ignoresSafeArea()

            // 살짝 살아있는 배경 보조(블러 원 두 개)
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 220, height: 220)
                    .blur(radius: 60)
                    .offset(x: -120, y: -220)
                    .opacity(glow ? 0.9 : 0.5)
                    .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: glow)

                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: 120, y: 180)
                    .opacity(glow ? 0.8 : 0.4)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: glow)
            }
            .allowsHitTesting(false)

            VStack(spacing: 24) {
                Spacer(minLength: 80)

                // ✅ 앱아이콘 카드(히어로) + 글로우 링
                ZStack {
                    // 카드
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 132, height: 132)
                        .shadow(color: .black.opacity(0.20), radius: 14, y: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.8)
                        )

                    // 로고
                    Image("AppLogo")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: 88, height: 88)

                    // 은은한 글로우 링
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.7), .clear],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing),
                                      lineWidth: 4)
                        .frame(width: 148, height: 148)
                        .blur(radius: 6)
                        .opacity(glow ? 0.9 : 0.4)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glow)
                }
                .opacity(showLogo ? 1 : 0)
                .scaleEffect(showLogo ? 1 : 0.92)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showLogo)

                // ✅ 카피(두 줄로 감정선)
                VStack(spacing: 10) {
                    Text("감정은 연결될 준비가 되어 있습니다")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(showCopy1 ? 1 : 0)
                        .offset(y: showCopy1 ? 0 : 6)
                        .animation(.easeOut(duration: 0.28).delay(0.10), value: showCopy1)

                    Text("지금, 당신의 1분을 WonderMinute에 맡겨보세요")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.85))
                        .opacity(showCopy2 ? 1 : 0)
                        .offset(y: showCopy2 ? 0 : 6)
                        .animation(.easeOut(duration: 0.28).delay(0.22), value: showCopy2)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

                // ✅ 진행 인디케이터(짧게 차오르고 라우팅)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 220 * progress, height: 6)
                        .animation(.easeInOut(duration: 1.6), value: progress)
                }
                .frame(width: 220, height: 6)
                .padding(.top, 8)
                .opacity(showCopy1 ? 1 : 0)

                Spacer()

                // ✅ 건너뛰기(디버그/테스트에도 유용)
                Button {
                    workItem?.cancel()
                    routeNext()
                } label: {
                    Text("건너뛰기")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                }
                .padding(.bottom, 36)
                .opacity(0.9)
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            // 모션 시작
            glow = true
            showLogo = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { showCopy1 = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { showCopy2 = true }

            // 진행바 & 라우팅
            progress = 0
            withAnimation { progress = 1 }

            let item = DispatchWorkItem { [weak appState] in
                guard let appState else { return }
                // Intro 화면에 머물러 있을 때만 라우팅
                if appState.currentView == .intro {
                    routeNext()
                }
            }
            workItem = item
            // 1.8초 정도 머물다 넘어감 (진행바와 맞춤)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: item)
        }
        .onDisappear {
            workItem?.cancel()
            workItem = nil
        }
    }

    private func routeNext() {
        // 인증 여부에 따라 다음 화면 결정
        if Auth.auth().currentUser == nil {
            withAnimation { appState.safeRouteToLoginIfNeeded() }   // 로그인/온보딩
        } else {
            withAnimation { appState.setView(.welcome, reason: "intro finished (authed)") }
        }
    }
}
