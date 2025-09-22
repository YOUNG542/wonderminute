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
            // ✅ 웜보이스 전역 배경(아이보리 그라데이션)
            GradientBackground()
                .ignoresSafeArea()

            // 살짝 살아있는 배경 보조(부드러운 아이보리/피치 글로우)
            ZStack {
                Circle()
                    .fill(AppTheme.ivoryTop.opacity(0.35))
                    .frame(width: 220, height: 220)
                    .blur(radius: 60)
                    .offset(x: -120, y: -220)
                    .opacity(glow ? 0.9 : 0.5)
                    .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: glow)

                Circle()
                    .fill(AppTheme.peach.opacity(0.25))
                    .frame(width: 260, height: 260)
                    .blur(radius: 70)
                    .offset(x: 120, y: 180)
                    .opacity(glow ? 0.8 : 0.4)
                    .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: glow)
            }
            .allowsHitTesting(false)

            VStack(spacing: 24) {
                Spacer(minLength: 80)

                // ✅ 앱 아이콘 카드(웜 스타일) + 글로우 링
                ZStack {
                    // 카드
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(red: 1.00, green: 0.99, blue: 0.97)) // 따뜻한 화이트
                        .frame(width: 132, height: 132)
                        .shadow(color: Color.black.opacity(0.16), radius: 14, y: 10)
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

                    // 은은한 글로우 링 (화이트 → 핑크/피치로 데님 톤 제거)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.70),
                                         AppTheme.pink.opacity(0.35),
                                         AppTheme.peach.opacity(0.0)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 148, height: 148)
                        .blur(radius: 6)
                        .opacity(glow ? 0.9 : 0.4)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glow)
                }
                .opacity(showLogo ? 1 : 0)
                .scaleEffect(showLogo ? 1 : 0.92)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showLogo)

                // ✅ 카피(웜 텍스트 컬러)
                VStack(spacing: 10) {
                    Text("마음을 털어놓는 순간, 연결이 시작됩니다")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary)
                        .opacity(showCopy1 ? 1 : 0)
                        .offset(y: showCopy1 ? 0 : 6)
                        .animation(.easeOut(duration: 0.28).delay(0.10), value: showCopy1)

                    Text("힘듦을 토로하면, 같은 마음의 누군가가 위로로 답해요")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .opacity(showCopy2 ? 1 : 0)
                        .offset(y: showCopy2 ? 0 : 6)
                        .animation(.easeOut(duration: 0.28).delay(0.22), value: showCopy2)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

                // ✅ 진행 인디케이터(배경: 글래스, 전경: 액센트 그라데이션)
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.glass)
                    // 그라데이션을 캡슐에 마스크
                    AppTheme.accentGradient
                        .frame(width: 220 * progress, height: 6)
                        .mask(Capsule())
                        .animation(.easeInOut(duration: 1.6), value: progress)
                }
                .frame(width: 220, height: 6)
                .padding(.top, 8)
                .opacity(showCopy1 ? 1 : 0)

                Spacer()

                // ✅ 건너뛰기(웜 톤)
                Button {
                    workItem?.cancel()
                    routeNext()
                } label: {
                    Text("건너뛰기")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.textPrimary.opacity(0.9))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(AppTheme.glass)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
                }
                .padding(.bottom, 36)
                .opacity(0.95)
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
            // 4초 정도 머물다 넘어감 (진행바와 맞춤)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: item)
        }
        .onDisappear {
            workItem?.cancel()
            workItem = nil
        }
    }

    private func routeNext() {
        // 인증 여부에 따라 다음 화면 결정 (동작 동일)
        if Auth.auth().currentUser == nil {
            withAnimation { appState.safeRouteToLoginIfNeeded() }   // 로그인/온보딩
        } else {
            withAnimation { appState.setView(.welcome, reason: "intro finished (authed)") }
        }
    }
}
