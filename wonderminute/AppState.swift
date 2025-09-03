import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import KakaoSDKUser
import AuthenticationServices
import AVFAudio
import AgoraRtcKit

typealias FirebaseUser = FirebaseAuth.User
typealias KakaoUser    = KakaoSDKUser.User

// ⬇️ AppState.swift 최상단(또는 AppState 선언 위)에 추가
struct ModerationState {
    var suspended: Bool = false
    var suspendedUntil: Date? = nil
    var permanentBan: Bool = false
    var scope: [String] = []            // ["match","message","call"] 등
    var reason: String? = nil           // 서버가 저장한 제재 사유(예: "폭언/혐오")
    var updatedAt: Date? = nil

    var isActiveSuspension: Bool {
        if permanentBan { return true }
        if let until = suspendedUntil { return Date() < until }
        return suspended
    }

    var remainingText: String {
        guard let until = suspendedUntil else { return permanentBan ? "영구 정지" : "제재 적용 중" }
        let sec = Int(until.timeIntervalSinceNow)
        if sec <= 0 { return "해제 대기 중…" }
        let d = sec / 86400, h = (sec % 86400) / 3600, m = (sec % 3600) / 60
        if d > 0 { return "\(d)일 \(h)시간 남음" }
        if h > 0 { return "\(h)시간 \(m)분 남음" }
        return "\(m)분 남음"
    }

    var humanReason: String { reason ?? "운영자 제재" }
    var scopeText: String {
        scope.isEmpty ? "앱 주요 기능 제한" : scope.joined(separator: " · ")
    }
}



final class AppState: ObservableObject {
    static let shared = AppState()
    
    // 네비 목적지
    enum AppRoute: Hashable { case callView }
    
    @Published var userRequestedMatching: Bool = false
    
    @Published var moderation = ModerationState()
    private var moderationListener: ListenerRegistration?
    
    // ⬅️ 배열 경로로 "한 번만" 선언
    @Published var path: [AppRoute] = [] {
        didSet { print("🧭 PATH \(oldValue) → \(path) at \(Date())") }
    }
    
    enum ViewType { case splash, welcome, login, userInfo, mainTabView, intro }
    @Published private(set) var currentView: ViewType = .splash
    @Published var isBootLoading: Bool = true
    
    // 매칭/큐 관련 (한 번만)
    @Published var isReadyForQueue: Bool = false
    
    // 단일 콜 인스턴스
    let callEngine = CallEngine()
    lazy var matchWatcher: MatchWatcher = MatchWatcher(call: callEngine)
    
    // 휴대폰 인증 상태
    @Published var showPhoneAuth = false
    var phoneAuthPurpose: String?
    var phoneAuthOnSuccess: (() -> Void)?
    var phoneAuthOnCancel: (() -> Void)?
    
    private var profileListener: ListenerRegistration?
    private var authListener: AuthStateDidChangeListenerHandle?
    
    // MARK: - Phone Auth helpers
    func presentPhoneAuthFlow(purpose: String,
                              onSuccess: @escaping () -> Void,
                              onCancel: @escaping () -> Void) {
        phoneAuthPurpose = purpose
        phoneAuthOnSuccess = onSuccess
        phoneAuthOnCancel  = onCancel
        showPhoneAuth = true
    }
    
    func completePhoneAuth(success: Bool) {
        if success { phoneAuthOnSuccess?() } else { phoneAuthOnCancel?() }
        phoneAuthPurpose = nil
        phoneAuthOnSuccess = nil
        phoneAuthOnCancel = nil
        showPhoneAuth = false
    }
    
    // MARK: - Centralized routing
    func setView(_ new: ViewType, reason: String) {
        // 🔇 동일 뷰 반복 라우팅 차단 → 로그 폭증 방지
        guard currentView != new else { return }
        let old = currentView
        print("🔁 Route \(old) → \(new) | reason: \(reason) | authed=\(Auth.auth().currentUser != nil)")
        currentView = new
    }
    
    func safeRouteToLoginIfNeeded() {
        if Auth.auth().currentUser == nil {
            setView(.login, reason: "intro finished → login")
        }
    }
    
    func logout() {
        UserDefaults.standard.removeObject(forKey: "lastLoginProvider")
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserApi.shared.logout { _ in }
        try? Auth.auth().signOut()
        stopProfileListener()
        
        // 🔁 경로 리셋: 배열 방식으로
        path.removeAll()
        
        setView(.welcome, reason: "user tapped logout")
        withAnimation { currentView = .welcome }
        isBootLoading = false
        isReadyForQueue = false
    }
    
    @MainActor
    func goToWelcome(reason: String = "force to welcome") {
        // 내비게이션 스택/상태를 먼저 정리
        path.removeAll()
        isBootLoading = false
        isReadyForQueue = false
        
        // 최종 목적지: Welcome
        setView(.welcome, reason: reason)
    }
    
    
    // MARK: - Lifecycle
    init() {
        print("🧠 AppState 초기화됨")
        prewarmForFirstCall()   // ✅ 딱 1번만
        SafetyCenter.shared.loadBlockedUids()
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            if let user = user {
                self.ensureUserDocAndMarkReady(user: user)
                SafetyCenter.shared.loadBlockedUids()
                self.startModerationListener()
                self.checkLoginStatus()
            } else {
                self.stopProfileListener()
                self.stopModerationListener()
                self.isReadyForQueue = false
                DispatchQueue.main.async {
                    self.isBootLoading = false
                    switch self.currentView {
                    case .userInfo, .mainTabView:
                        // 🔁 경로 리셋: 배열 방식
                        self.path.removeAll()
                        self.setView(.welcome, reason: "auth=nil while in protected view")
                    case .splash, .welcome, .login, .intro:
                        break
                    }
                }
            }
        }
    }
    
    deinit {
        stopProfileListener()
        if let h = authListener { Auth.auth().removeStateDidChangeListener(h) }
    }
    
    private func stopProfileListener() {
        profileListener?.remove()
        profileListener = nil
    }
    
    // MARK: - Auth / Provider → Profile → Routing
    private func checkLoginStatus() {
        print("🔍 로그인/자격 상태 확인 중…")
        
        guard Auth.auth().currentUser != nil else {
            DispatchQueue.main.async {
                self.isBootLoading = false
                if case .userInfo = self.currentView { self.setView(.welcome, reason: "no auth from checkLoginStatus") }
                if case .mainTabView = self.currentView { self.setView(.welcome, reason: "no auth from checkLoginStatus") }
            }
            return
        }
        
        isBootLoading = true
        
        let lastProvider = UserDefaults.standard.string(forKey: "lastLoginProvider")
        switch lastProvider {
        case "apple":  checkAppleCredentialState()
        case "kakao":  checkKakaoToken()
        default:       observeProfileAndRoute()
        }
    }
    
    private func checkAppleCredentialState() {
        let provider = ASAuthorizationAppleIDProvider()
        guard let appleUserID = UserDefaults.standard.string(forKey: "appleUserID") else {
            print("⚠️ appleUserID 없음 → 프로필 기준 라우팅")
            observeProfileAndRoute()
            return
        }
        
        provider.getCredentialState(forUserID: appleUserID) { state, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("⚠️ Apple credential check failed: \(error.localizedDescription) → 프로필 기준")
                    self.observeProfileAndRoute(); return
                }
                switch state {
                case .authorized: print("✅ Apple authorized"); self.observeProfileAndRoute()
                case .revoked, .notFound, .transferred: print("⚠️ Apple state=\(state)"); self.observeProfileAndRoute()
                @unknown default: print("⚠️ Apple unknown"); self.observeProfileAndRoute()
                }
            }
        }
    }
    
    private func checkKakaoToken() {
        UserApi.shared.accessTokenInfo { _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("⚠️ Kakao token check failed: \(error.localizedDescription) → 프로필 기준")
                } else {
                    print("✅ Kakao authorized → 프로필 기준")
                }
                self.observeProfileAndRoute()
            }
        }
    }
    
    private func observeProfileAndRoute() {
        stopProfileListener()
        guard let uid = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                self.isBootLoading = false
                self.setView(.welcome, reason: "observeProfileAndRoute: uid nil")
            }
            return
        }
        
        let ref = Firestore.firestore().collection("users").document(uid)
        profileListener = ref.addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let err = err {
                    print("⚠️ 프로필 스냅샷 에러: \(err.localizedDescription) → userInfo")
                    self.isBootLoading = false
                    self.setView(.userInfo, reason: "profile snapshot error")
                    return
                }
                
                let completed = (snap?.data()?["profileCompleted"] as? Bool) ?? false
                let target: ViewType = completed ? .mainTabView : .userInfo
                self.isBootLoading = false
                // 🔇 동일 타겟이면 라우팅/로그 생략
                if self.currentView != target {
                    self.setView(target,
                                 reason: completed ? "profileCompleted=true" : "profile not completed")
                }
            }
        }
    }
    
    func fetchUserInfoAndGoToMain() {
        print("👤 AppState 사용자 정보 테스트 호출")
        UserApi.shared.me { (user, error) in
            if let error = error {
                print("❌ 사용자 정보 가져오기 실패: \(error)"); return
            }
            guard let user = user,
                  let nickname = user.kakaoAccount?.profile?.nickname else {
                print("❌ 사용자 정보 누락"); return
            }
            print("✅ 사용자 정보: \(nickname)")
            withAnimation { self.setView(.mainTabView, reason: "manual jump") }
        }
    }
    
    private func ensureUserDocAndMarkReady(user: FirebaseUser) {
        let ref = Firestore.firestore().collection("users").document(user.uid)
        ref.setData([
            "uid": user.uid,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ], merge: true) { err in
            if let err = err {
                print("❌ ensure user doc failed:", err.localizedDescription)
                DispatchQueue.main.async { self.isReadyForQueue = false }
                return
            }
            
            user.getIDToken { _, tokenErr in
                if let tokenErr = tokenErr {
                    print("❌ getIDToken failed:", tokenErr.localizedDescription)
                    DispatchQueue.main.async { self.isReadyForQueue = false }
                    return
                }
                print("✅ Auth + user doc ready → isReadyForQueue = true")
                DispatchQueue.main.async { self.isReadyForQueue = true }
            }
        }
    }
    func pushOnce(_ route: AppRoute, reason: String) {
        let last = path.last
        print("🧭 pushOnce request route=\(route) last=\(String(describing: last)) reason=\(reason) path.count=\(path.count)")
        if last == route {
            print("🧭 SKIP push (same last)")
            return
        }
        path.append(route)
        print("🧭 APPENDED route=\(route) path.count=\(path.count)")
    }
    // MARK: - Auto Matching control
    @MainActor
    func stopAutoMatching(alsoCancelQueue: Bool = false) {
        if userRequestedMatching {
            print("🛑 stopAutoMatching – turn off flags (alsoCancelQueue=\(alsoCancelQueue))")
        }
        // 자동매칭 플래그 OFF
        userRequestedMatching = false
        
        // (선택) 콜 상태 신호도 리셋 — 다음 매칭 때만 다시 뜨도록
        callEngine.currentRoomId = nil
        callEngine.remoteEnded   = false
        
        // (선택) 서버 큐까지 정리하고 싶으면 true로 호출
        if alsoCancelQueue {
            FunctionsAPI.cancelMatch()
        }
    }
    private func prewarmForFirstCall() {
        // 오디오 세션 경로 내재 캐시
        DispatchQueue.global(qos: .utility).async {
            _ = AVAudioSession.sharedInstance().sampleRate
        }
        // Agora 엔진 JIT 로딩만 끝내고 즉시 파괴 (실접속 아님)
        DispatchQueue.global(qos: .utility).async {
            let tmp = AgoraRtcEngineKit.sharedEngine(withAppId: "eb7e807372f94d8596d271f5bccbd268", delegate: nil)
            AgoraRtcEngineKit.destroy()
        }
        // GCD 타이머 경로 워밍업(미세)
        let s = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        s.schedule(deadline: .now() + .milliseconds(10))
        s.setEventHandler {}
        s.resume()
        s.cancel()
    }
    // ⬇️ AppState.swift 맨 아래쪽에 추가
    private func startModerationListener() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        moderationListener?.remove()
        moderationListener = Firestore.firestore().collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self = self else { return }
                guard let data = snap?.data(), let mod = data["moderation"] as? [String: Any] else {
                    self.moderation = ModerationState(); return
                }
                let suspended     = (mod["suspended"] as? Bool) ?? false
                let permanentBan  = (mod["permanentBan"] as? Bool) ?? false
                let until         = (mod["suspendedUntil"] as? Timestamp)?.dateValue()
                let scope         = (mod["scope"] as? [String]) ?? []
                let reason        = (mod["reason"] as? String)          // 서버에 저장한 제재 사유(있으면 표시)
                let updatedAt     = (mod["updatedAt"] as? Timestamp)?.dateValue()

                self.moderation = ModerationState(
                    suspended: suspended,
                    suspendedUntil: until,
                    permanentBan: permanentBan,
                    scope: scope,
                    reason: reason,
                    updatedAt: updatedAt
                )
            }
    }

    private func stopModerationListener() {
        moderationListener?.remove()
        moderationListener = nil
    }

}


