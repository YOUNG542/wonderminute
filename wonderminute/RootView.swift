import SwiftUI
import KakaoSDKAuth

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    
    
    var body: some View {
        // ✨ 전역 NavigationStack 적용
        NavigationStack(path: $appState.path) {
            ZStack {
                if appState.isBootLoading {
                    ProgressView("Loading...")
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    switch appState.currentView {
                        
                    case .splash:
                        IntroSplashView()                         // ← 새로 추가
                            .transition(.opacity)
                    case .welcome:
                        WelcomeView()

                    case .login:
                        LoginView()

                    case .userInfo:
                        UserInfoView()

                    case .mainTabView:
                        MainTabView()

                    case .intro:
                        IntroAnimationView()
                    }
                }
            }
            .navigationDestination(for: AppState.AppRoute.self) { route in
                switch route {
                case .callView:
                    CallView(call: appState.callEngine,
                             watcher: appState.matchWatcher)
                }
            }

        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                CallLifecycle.shared.willEnterBackground()
            }
        }
        
    }
}
