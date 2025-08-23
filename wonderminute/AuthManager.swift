import Foundation
import UIKit
import AuthenticationServices
import CryptoKit

import FirebaseAuth

import KakaoSDKAuth
import KakaoSDKUser

enum LoginProvider: String {
    case apple
    case kakaoCustom
    case unknown
}

final class AuthManager: NSObject {
    static let shared = AuthManager()
    private override init() {}

    // 마지막 로그인 수단 저장(선택) — 로그인 성공 시 setLastProvider 호출
    private let lastProviderKey = "auth.lastProvider"

    func setLastProvider(_ p: LoginProvider) {
        UserDefaults.standard.set(p.rawValue, forKey: lastProviderKey)
    }
    private func lastProvider() -> LoginProvider? {
        guard let raw = UserDefaults.standard.string(forKey: lastProviderKey) else { return nil }
        return LoginProvider(rawValue: raw)
    }

    // Firebase providerData로 추정 (보조 수단)
    private func detectFromFirebase() -> LoginProvider {
        guard let user = Auth.auth().currentUser else { return .unknown }
        let providers = user.providerData.map { $0.providerID } // e.g. "apple.com", "custom"
        if providers.contains("apple.com") { return .apple }
        if providers.contains("custom")    { return .kakaoCustom }
        return .unknown
    }

    private func detectProvider() -> LoginProvider {
        if let s = lastProvider() { return s }
        return detectFromFirebase()
    }

    // MARK: - Public
    @MainActor
    func reauthenticateUser(preferred: LoginProvider? = nil) async throws {
        switch preferred ?? detectProvider() {
        case .apple:        try await reauthWithApple()
        case .kakaoCustom:  try await reauthWithKakaoCustomToken()
        case .unknown:
            throw NSError(domain: "Reauth", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "재인증 수단을 확인할 수 없습니다. 애플 또는 카카오로 다시 로그인해주세요."])
        }
    }

    // MARK: - Apple (Sign in with Apple)
    private var currentNonce: String?

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var rnd: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &rnd)
            if rnd < charset.count {
                result.append(charset[Int(rnd)])
                remaining -= 1
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private func reauthWithApple() async throws {
        let nonce = randomNonceString()
        currentNonce = nonce

        let req = ASAuthorizationAppleIDProvider().createRequest()
        req.requestedScopes = []             // 재인증: 개인정보 스코프 불필요
        req.nonce = sha256(nonce)

        let ctrl = ASAuthorizationController(authorizationRequests: [req])
        let delegate = AppleAuthContinuationDelegate()
        ctrl.delegate = delegate
        ctrl.presentationContextProvider = delegate
        ctrl.performRequests()

        let result = try await delegate.result()

        guard
            let cred = result.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = cred.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let rawNonce = currentNonce
        else {
            throw NSError(domain: "Reauth", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "애플 토큰을 가져오지 못했습니다."])
        }

        let appleCred = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: nil
        )

        try await Auth.auth().currentUser?.reauthenticate(with: appleCred)
        setLastProvider(.apple)
    }

    private final class AppleAuthContinuationDelegate: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        private var cont: CheckedContinuation<ASAuthorization, Error>?

        func result() async throws -> ASAuthorization {
            try await withCheckedThrowingContinuation { c in self.cont = c }
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? UIWindow()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            cont?.resume(returning: authorization); cont = nil
        }
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            cont?.resume(throwing: error); cont = nil
        }
    }

    // MARK: - Kakao (커스텀 토큰)
    /// 🔧 프로젝트 백엔드의 커스텀 토큰 발급 API URL로 바꾸세요.
    // ❶ 커스텀 토큰 발급 엔드포인트 (네가 쓰는 로그인과 동일)
    private let customTokenEndpoint = URL(string: "https://kakaologin-gb7ac7hw7q-uc.a.run.app")!

   
    // ❷ 카카오 커스텀 재인증
    private func reauthWithKakaoCustomToken() async throws {
        let kakao = try await kakaoLoginOrRefresh() // 카카오 SDK로 accessToken 확보
        let customToken = try await fetchFirebaseCustomToken(kakaoAccessToken: kakao.accessToken)
        _ = try await Auth.auth().signIn(withCustomToken: customToken) // 재로그인=재인증
        setLastProvider(.kakaoCustom)
    }

    private func kakaoLoginOrRefresh() async throws -> OAuthToken {
        try await withCheckedThrowingContinuation { cont in
            if AuthApi.hasToken() {
                UserApi.shared.accessTokenInfo { _, error in
                    if error != nil {
                        UserApi.shared.loginWithKakaoAccount { tok, err in
                            if let err = err { cont.resume(throwing: err) }
                            else if let tok = tok { cont.resume(returning: tok) }
                            else { cont.resume(throwing: NSError(domain: "Kakao", code: -1)) }
                        }
                    } else {
                        UserApi.shared.loginWithKakaoAccount { tok, err in
                            if let err = err { cont.resume(throwing: err) }
                            else if let tok = tok { cont.resume(returning: tok) }
                            else { cont.resume(throwing: NSError(domain: "Kakao", code: -2)) }
                        }
                    }
                }
            } else {
                UserApi.shared.loginWithKakaoAccount { tok, err in
                    if let err = err { cont.resume(throwing: err) }
                    else if let tok = tok { cont.resume(returning: tok) }
                    else { cont.resume(throwing: NSError(domain: "Kakao", code: -3)) }
                }
            }
        }
    }

    // ❸ 백엔드 호출부: 로그인 때와 동일 스펙으로 호출
    private func fetchFirebaseCustomToken(kakaoAccessToken: String) async throws -> String {
        var req = URLRequest(url: customTokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("kim791030!!!", forHTTPHeaderField: "x-secret")     // ✅ 동일 헤더
        let body = ["token": kakaoAccessToken]                            // ✅ 동일 바디 키
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "CustomToken", code: -10,
                          userInfo: [NSLocalizedDescriptionKey: "커스텀 토큰 발급 실패"])
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["firebase_token"] as? String else {        // ✅ 동일 응답 키
            throw NSError(domain: "CustomToken", code: -11,
                          userInfo: [NSLocalizedDescriptionKey: "firebase_token 키가 없습니다"])
        }
        return token
    }
}
