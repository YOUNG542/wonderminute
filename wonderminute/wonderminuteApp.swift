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
            RootView()
                            .tint(.white)
                            .environmentObject(AppState.shared)
                            // ✅ 카카오 콜백 (커스텀 스킴)
                            .onOpenURL { url in
                                print("↩️ [Kakao] onOpenURL:", url.absoluteString)
                                if AuthApi.isKakaoTalkLoginUrl(url) {
                                    _ = AuthController.handleOpenUrl(url: url)
                                }
                            }
                            // ✅ 카카오 콜백 (Universal Link)
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
