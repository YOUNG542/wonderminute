import UIKit
import KakaoSDKCommon
import KakaoSDKAuth

import FirebaseCore
import FirebaseAppCheck
import FirebaseAuth
import FirebaseMessaging   // ✅ 추가
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // Firebase
        FirebaseApp.configure()
        FirebaseConfiguration.shared.setLoggerLevel(.debug)
        print("🔥 Firebase logger=DEBUG at \(Date())")

        // App Check
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        if #available(iOS 14.0, *) {
          AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        } else {
          // 구형 기기 대비 폴백(최소 타깃이 14+면 이 줄들 삭제해도 됨)
          AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        }
        #endif


        // Kakao
        KakaoSDK.initSDK(appKey: "b8cf7168ac44379964e92c80071dbaf1")

        // 알림 권한 + APNs 등록
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, err in
            print("🔔 APNs auth granted=\(granted) err=\(String(describing: err))")
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }

        // FCM delegate
        Messaging.messaging().delegate = self

        // 로그인 상태가 바뀔 때마다 최신 FCM 토큰을 사용자 문서에 저장
        Auth.auth().addStateDidChangeListener { _, user in
            guard let user else { return }
            Messaging.messaging().token { token, error in
                if let t = token, error == nil {
                    saveFcmToken(uid: user.uid, token: t)
                }
            }
        }

        return true
    }

    // APNs 토큰 → FirebaseAuth(PhoneAuth 용)
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif
        print("📮 APNs token set len=\(deviceToken.count)")
    }

    // FirebaseAuth(PhoneAuth) 우선 처리
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let handled = Auth.auth().canHandleNotification(userInfo)
        if handled { completionHandler(.noData); return }
        completionHandler(.noData)
    }

    // 포그라운드에서도 배너/사운드 보이게
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    // FCM 토큰 리프레시 콜백
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let uid = Auth.auth().currentUser?.uid, let t = fcmToken else { return }
        saveFcmToken(uid: uid, token: t)
        print("✅ FCM token refreshed & saved")
    }

    // 외부 URL 콜백 (FirebaseAuth → Kakao 순서)
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        if Auth.auth().canHandle(url) { return true }
        if AuthApi.isKakaoTalkLoginUrl(url) { return AuthController.handleOpenUrl(url: url) }
        return false
    }
}

// MARK: - Firestore에 FCM 토큰 저장
import FirebaseFirestore
private func saveFcmToken(uid: String, token: String) {
    let db = Firestore.firestore()
    db.collection("users").document(uid)
        .collection("fcmTokens").document(token)
        .setData(["updatedAt": FieldValue.serverTimestamp()], merge: true) { err in
            if let err { print("⚠️ saveFcmToken error:", err.localizedDescription) }
        }
}
