import SwiftUI
import UIKit
import FirebaseAuth
import KakaoSDKAuth 
@main
struct WonderMinuteApp: App {
    // 기존과 동일하게 AppDelegate 쓰는 경우 유지
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        // 전역 Tint (버튼/토글 등)
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = .white
        UINavigationBar.appearance().tintColor = .white
        UITabBar.appearance().unselectedItemTintColor = UIColor.white.withAlphaComponent(0.6)
    }

    var body: some Scene {
        WindowGroup {
            AppEntryGate {                      // ⬅️ 추가: 게이트
                RootView()                      // 원래 컨텐츠는 그대로
            }
            .tint(.white)
            .environmentObject(AppState.shared)
            // ✅ 카카오 콜백
            .onOpenURL { url in
                print("↩️ [Kakao] onOpenURL:", url.absoluteString)
                if AuthApi.isKakaoTalkLoginUrl(url) {
                    _ = AuthController.handleOpenUrl(url: url)
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL {
                    print("↩️ [Kakao] continueUserActivity:", url.absoluteString)
                    if AuthApi.isKakaoTalkLoginUrl(url) {
                        _ = AuthController.handleOpenUrl(url: url)
                    }
                }
            }
        }

                }
}

// ⬇️ wonderminuteApp.swift 파일 맨 아래에 추가
struct AppEntryGate<Content: View>: View {
    @EnvironmentObject private var appState: AppState
    let content: () -> Content
    var body: some View {
        Group {
            if appState.moderation.isActiveSuspension {
                SuspendedGateView(m: appState.moderation)   // ⬅️ 진입 차단 화면
            } else {
                content()                                   // 정상 앱 콘텐츠
            }
        }
    }
}
