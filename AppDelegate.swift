import UIKit
import KakaoSDKCommon
import KakaoSDKAuth

import FirebaseCore
import FirebaseAppCheck
import FirebaseAuth
import UserNotifications   // ✅ 추가
import Firebase

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // ✅ Firebase 초기화
        FirebaseApp.configure()
        
        // ✅ Firebase 디버그 로그 활성화
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
        print("🔥 Firebase logger=DEBUG at \(Date())")


        // ✅ App Check 설정
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif

        // ✅ Kakao SDK 초기화
        KakaoSDK.initSDK(appKey: "b8cf7168ac44379964e92c80071dbaf1")

        // ✅ 원격 푸시 등록 (APNs) — Phone Auth에 필요
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, err in
          print("🔔 APNs auth granted=\(granted) err=\(String(describing: err)) at \(Date())")
          DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
          }
        }

        return true
    }

    // ✅ APNs 토큰을 FirebaseAuth(PhoneAuth)로 전달
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif
        print("📮 APNs token set len=\(deviceToken.count)")
    }

    // ✅ 원격 알림 수신 시 PhoneAuth에 먼저 전달
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let handled = Auth.auth().canHandleNotification(userInfo)
        print("📩 didReceiveRemoteNotification handledByAuth=\(handled) userInfoKeys=\(userInfo.keys)")
        if handled { completionHandler(.noData); return }
        completionHandler(.noData)

    }

    // ✅ 외부 URL 콜백 처리 (FirebaseAuth → Kakao 순서 유지)
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        print("📥 AppDelegate openURL 진입됨: \(url)")

        // Firebase Phone Auth reCAPTCHA 콜백 우선
        if Auth.auth().canHandle(url) {
            print("✅ FirebaseAuth handled URL")
            return true
        }

        // Kakao 로그인 콜백
        if AuthApi.isKakaoTalkLoginUrl(url) {
            print("✅ KakaoTalk 로그인 URL 감지됨")
            let result = AuthController.handleOpenUrl(url: url)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AppState.shared.fetchUserInfoAndGoToMain()
            }
            return result
        }

        print("❌ 처리할 수 없는 URL")
        return false
    }
}
