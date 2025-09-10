import SwiftUI
import KakaoSDKAuth
import KakaoSDKUser
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
import FirebaseAppCheck

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var isLoading = false
    
    // ✅ 여기에 추가
      @State private var currentReqId = ""           // 요청 단위 상관아이디
      @State private var loginTimeout: DispatchWorkItem?

    // Apple Sign-In nonce
    @State private var currentNonce: String?

    // Anim
    @State private var appearLogo = false
    @State private var appearButtons = false
    @State private var glow = false

    // Sheets
    @State private var showPrivacy = false
    @State private var showTerms = false

    var body: some View {
        ZStack {
            GradientBackground().ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer(minLength: 44)

                // 아이콘 카드
                LoginAppIconCard(logoName: "AppLogo", cardSize: 124, logoSize: 82, corner: 24, glow: glow)
                    .opacity(appearLogo ? 1 : 0)
                    .scaleEffect(appearLogo ? 1 : 0.94)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: appearLogo)

                Text("지금 연결을 시작해보세요")
                    .font(.title3.bold())
                    .foregroundColor(AppTheme.textPrimary)
                    .opacity(appearLogo ? 1 : 0)
                    .offset(y: appearLogo ? 0 : 6)
                    .animation(.easeOut(duration: 0.25).delay(0.05), value: appearLogo)
                    .padding(.top, 6)
             

                // 로그인 버튼들
                VStack(spacing: 10) {
                    // 카카오
                    Button(action: { kakaoLogin() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "message.fill")
                            Text("카카오로 시작하기").bold()
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    }
                    .padding(.horizontal, 24)

                    // 애플
                    if #available(iOS 13.0, *) {
                        SignInWithAppleButton(.signIn,
                          onRequest: { req in
                            let nonce = randomNonceString()
                            currentNonce = nonce
                            req.requestedScopes = [.fullName, .email]
                            req.nonce = sha256(nonce) // 서버에서 claims.nonce와 비교
                            isLoading = true
                          },
                          onCompletion: { result in
                            switch result {
                            case .success(let auth):
                              guard
                                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                                let tokenData = credential.identityToken,
                                let idTokenString = String(data: tokenData, encoding: .utf8),
                                let rawNonce = currentNonce
                              else {
                                self.isLoading = false
                                return
                              }

                                // 1) check 모드 호출
                                if var comps = URLComponents(string: "https://us-central1-wonderminute-7a4c9.cloudfunctions.net/appleLogin") {
                                    comps.queryItems = [URLQueryItem(name: "mode", value: "check")]
                                    guard let checkURL = comps.url else { self.isLoading = false; return }

                                    var checkReq = URLRequest(url: checkURL)
                                    checkReq.httpMethod = "POST"
                                    checkReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                                    let body: [String: Any] = [
                                      "identityToken": idTokenString,
                                      "rawNonceHash": sha256(rawNonce)
                                    ]
                                    checkReq.httpBody = try? JSONSerialization.data(withJSONObject: body)

                                    withAppCheckHeader(checkReq) { signed in
                                        URLSession.shared.dataTask(with: signed) { data, _, error in
                                            if let error = error { print("appleLogin(check) req error:", error); DispatchQueue.main.async { self.isLoading = false }; return }
                                            guard let data = data,
                                                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { DispatchQueue.main.async { self.isLoading = false }; return }

                                            let bound = (json["bound"] as? Bool) ?? false
                                            if bound, let customToken = json["firebase_token"] as? String {
                                                // 즉시 로그인
                                                Auth.auth().signIn(withCustomToken: customToken) { result, error in
                                                    DispatchQueue.main.async { self.isLoading = false }
                                                    if let error = error { print("Firebase custom signIn error:", error); return }
                                                    if let uid = result?.user.uid { checkUserInfoExists(uid: uid) }
                                                }
                                            } else {
                                                // 미바인드 → 번호 인증 후 바인드
                                                DispatchQueue.main.async {
                                                    self.isLoading = false
                                                    AppState.shared.presentPhoneAuthFlow(
                                                        purpose: "계정 확인",
                                                        onSuccess: {
                                                            self.finalizeBindApple(identityToken: idTokenString, rawNonceHash: sha256(rawNonce))
                                                        },
                                                        onCancel: { /* no-op */ }
                                                    )
                                                }
                                            }
                                        }.resume()
                                    }
                                }

                                

                            case .failure(let e):
                              print("Apple Sign-In failed:", e.localizedDescription)
                              self.isLoading = false
                            }
                          }
                        )

                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 24)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

                    }
                }
                .opacity(appearButtons ? 1 : 0)
                .offset(y: appearButtons ? 0 : 8)
                .animation(.easeOut(duration: 0.28).delay(0.12), value: appearButtons)

                // 약관 고지
                ConsentNotice(showPrivacy: $showPrivacy, showTerms: $showTerms)
                    .opacity(appearButtons ? 1 : 0)
                    .animation(.easeOut(duration: 0.25).delay(0.16), value: appearButtons)

                Spacer(minLength: 20)
            }

        
            // 로딩 (앱 톤에 맞춘 글래스 카드 + 로고 링 스피너)
            if isLoading {
                LoadingOverlay(
                    title: "로그인 중…",
                    subtitle: "보안을 위해 App Check와 계정 상태를 확인하는 중입니다"
                )
                .transition(.opacity)
            }

        }
        .sheet(isPresented: $showPrivacy) {
            NavigationView {
                PrivacyPolicyView()
                    .navigationTitle("개인정보처리방침")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showTerms) {
            NavigationView {
                TermsOfServiceView()
                    .navigationTitle("이용약관")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        // ✅ [추가] 전화번호 인증 화면
        .fullScreenCover(isPresented: $appState.showPhoneAuth) {
            NavigationView {
                PhoneVerifyView { _ in                 // onVerified 콜백
                    appState.completePhoneAuth(success: true)
                }
                .navigationTitle(appState.phoneAuthPurpose ?? "계정 확인")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { appState.completePhoneAuth(success: false) }
                    }
                }
            }
        }

        .onAppear {
            appearLogo = true
            appearButtons = true
            glow = true
        }

    }

    // MARK: - Diagnostics (요기 추가)
    private func newReqId() -> String {
        let id = UUID().uuidString
        currentReqId = id
        return id
    }

    private func endLoading() {
        loginTimeout?.cancel()
        loginTimeout = nil
        isLoading = false
    }

    
    // MARK: Kakao
    func kakaoLogin() {
        isLoading = true
        let rid = newReqId()
        print("▶️ [\(rid)] Kakao login tapped")

        // 20초 타임아웃으로 무한로딩 차단
        let w = DispatchWorkItem { [rid] in
            print("⏰ [\(rid)] LOGIN TIMEOUT")
            endLoading()
        }
        loginTimeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)

        if UserApi.isKakaoTalkLoginAvailable() {
            UserApi.shared.loginWithKakaoTalk { oauthToken, error in
                self.handleKakaoLoginResult(oauthToken: oauthToken, error: error)
            }
        } else {
            UserApi.shared.loginWithKakaoAccount { oauthToken, error in
                self.handleKakaoLoginResult(oauthToken: oauthToken, error: error)
            }
        }
    }

    func handleKakaoLoginResult(oauthToken: OAuthToken?, error: Error?) {
        if let error = error {
            print("❌ [\(currentReqId)] Kakao OAuth failed: \(error.localizedDescription)")
            endLoading(); return
        }
        guard let accessToken = oauthToken?.accessToken else {
            print("❌ [\(currentReqId)] Kakao OAuth ok but accessToken missing")
            endLoading(); return
        }
        print("✅ [\(currentReqId)] Kakao OAuth ok. tokenLen=\(accessToken.count)")
        loginWithFirebase(using: accessToken)
    }

    func loginWithFirebase(using kakaoAccessToken: String) {
        // 1) 사전조회(check)
        guard let base = URL(string: "https://kakaologin-gb7ac7hw7q-uc.a.run.app"),
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            print("❌ [\(currentReqId)] invalid kakaoLogin URL")
            endLoading(); return
        }
        comps.queryItems = [URLQueryItem(name: "mode", value: "check")]
        guard let checkURL = comps.url else { endLoading(); return }

        var checkReq = URLRequest(url: checkURL)
        checkReq.timeoutInterval = 15
        checkReq.httpMethod = "POST"
        checkReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        checkReq.setValue(currentReqId, forHTTPHeaderField: "X-Req-Id")
        checkReq.httpBody = try? JSONSerialization.data(withJSONObject: ["token": kakaoAccessToken])

        withAppCheckHeader(checkReq) { signed in
            URLSession.shared.dataTask(with: signed) { data, resp, error in
                if let http = resp as? HTTPURLResponse { print("🌐 [\(self.currentReqId)] kakaoLogin(check) HTTP \(http.statusCode)") }
                if let e = error { print("❌ check req error:", e.localizedDescription); DispatchQueue.main.async { self.endLoading() }; return }
                guard let data = data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any] else {
                    DispatchQueue.main.async { self.endLoading() }; return
                }
                let bound = (json["bound"] as? Bool) ?? false
                if bound, let customToken = json["firebase_token"] as? String {
                    // 이미 묶여있음 → 즉시 로그인
                    if Auth.auth().currentUser != nil { try? Auth.auth().signOut() }
                    print("🔐 [\(self.currentReqId)] Firebase signIn starts")
                    Auth.auth().signIn(withCustomToken: customToken) { result, error in
                        if let error = error {
                            print("❌ [\(self.currentReqId)] Firebase signIn error: \(error.localizedDescription)")
                            DispatchQueue.main.async { self.endLoading() }
                            return
                        }
                        let uid = result?.user.uid ?? "nil"
                        let providers = result?.user.providerData.map { $0.providerID } ?? []
                        print("✅ [\(self.currentReqId)] Firebase signIn ok uid=\(uid) providers=\(providers)")
                        self.checkUserInfoExists(uid: uid)
                    }
                } else {
                    // 아직 미바인드 → 번호 인증 화면으로 전환 후, 성공 시 바인드 호출
                    DispatchQueue.main.async {
                        self.endLoading()
                        AppState.shared.presentPhoneAuthFlow(
                            purpose: "계정 확인",
                            onSuccess: {
                                self.finalizeBindKakao(accessToken: kakaoAccessToken)
                            },
                            onCancel: { /* no-op */ }
                        )
                    }
                }
            }.resume()
        }
    }

    // ★ 번호 인증 성공 후 호출: Authorization 헤더로 바인드
    private func finalizeBindKakao(accessToken: String) {
        guard let url = URL(string: "https://kakaologin-gb7ac7hw7q-uc.a.run.app") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(currentReqId, forHTTPHeaderField: "X-Req-Id")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["token": accessToken])

        withAuthAndAppCheck(req) { signed in
            URLSession.shared.dataTask(with: signed) { data, resp, error in
                if let http = resp as? HTTPURLResponse { print("🌐 [\(self.currentReqId)] kakaoLogin(bind) HTTP \(http.statusCode)") }
                if let e = error { print("❌ bind req error:", e.localizedDescription); return }
                guard let data = data,
                      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any] else { return }

                // 이미 번호인증으로 로그인된 상태라면 재로그인 불필요
                // 필요하면 아래처럼 firebase_token으로 재로그인할 수도 있음
                if Auth.auth().currentUser == nil, let token = json["firebase_token"] as? String {
                    Auth.auth().signIn(withCustomToken: token) { _, _ in
                        if let uid = Auth.auth().currentUser?.uid { self.checkUserInfoExists(uid: uid) }
                    }
                } else {
                    if let uid = Auth.auth().currentUser?.uid { self.checkUserInfoExists(uid: uid) }
                }
            }.resume()
        }
    }
    
    // ★ 번호인증 성공 후 Apple 바인드
    private func finalizeBindApple(identityToken: String, rawNonceHash: String) {
        guard let url = URL(string: "https://us-central1-wonderminute-7a4c9.cloudfunctions.net/appleLogin") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
          "identityToken": identityToken,
          "rawNonceHash": rawNonceHash
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        withAuthAndAppCheck(req) { signed in
            URLSession.shared.dataTask(with: signed) { data, _, error in
                if let error = error { print("appleLogin(bind) req error:", error); return }
                // 이미 번호인증으로 로그인된 상태 → 그대로 프로필로
                if let uid = Auth.auth().currentUser?.uid {
                    self.checkUserInfoExists(uid: uid)
                }
            }.resume()
        }
    }



    // MARK: Firestore
    func checkUserInfoExists(uid: String) {
        print("👤 [\(currentReqId)] check user doc uid=\(uid)")
        let ref = Firestore.firestore().collection("users").document(uid)
        ref.getDocument { document, _ in
            DispatchQueue.main.async {
                self.endLoading()

                // 문서가 아예 없으면 → 온보딩
                guard let d = document, d.exists else {
                    print("🏁 [\(self.currentReqId)] no user doc → userInfo")
                    withAnimation { self.appState.setView(.userInfo, reason: "login → no profile yet") }
                    return
                }

                // ✅ 필수 필드 기준으로 '완료' 판정
                let nickname = d.get("nickname") as? String ?? ""
                let gender   = d.get("gender") as? String ?? ""
                let completed = d.get("profileCompleted") as? Bool ?? false

                let hasRequired = !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && !gender.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

                if completed && hasRequired {
                    print("🏁 [\(self.currentReqId)] profile complete → mainTabView")
                    withAnimation { self.appState.setView(.mainTabView, reason: "login → profile exists") }
                } else {
                    print("🏁 [\(self.currentReqId)] profile incomplete → userInfo")
                    withAnimation { self.appState.setView(.userInfo, reason: "login → profile incomplete") }
                }
            }
        }
    }


    // MARK: Nonce
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var random: UInt8 = 0
            let err = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if err != errSecSuccess { fatalError("Unable to generate nonce.") }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Private subviews (이 파일 전용)

fileprivate struct LoginAppIconCard: View {
    let logoName: String
    let cardSize: CGFloat
    let logoSize: CGFloat
    let corner: CGFloat
    var glow: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color(red: 1.00, green: 0.99, blue: 0.97)) // 따뜻한 화이트
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

            RoundedRectangle(cornerRadius: corner + 4, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [
                        Color.white.opacity(0.7),
                        AppTheme.pink.opacity(0.35),
                        AppTheme.peach.opacity(0.0)
                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 4
                )

                .frame(width: cardSize + 20, height: cardSize + 20)
                .blur(radius: 6)
                .opacity(glow ? 0.9 : 0.4)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glow)
        }
    }
}

// MARK: - Loading Overlay (글래스 카드 + 로고 링 스피너)
fileprivate struct LoadingOverlay: View {
    let title: String
    let subtitle: String?

    @State private var spin = false

    var body: some View {
        ZStack {
            // 배경 딤 + 미세 그레인
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 14) {
                // 로고 + 링 스피너
                ZStack {
                    Circle()
                        .fill(AppTheme.peach.opacity(0.12))
                        .frame(width: 74, height: 74)


                    // 회전 링
                    Circle()
                        .trim(from: 0.08, to: 0.92)
                        .stroke(style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(width: 74, height: 74)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.05).repeatForever(autoreverses: false), value: spin)

                    // 앱 로고 (있는 경우)
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .shadow(color: .white.opacity(0.25), radius: 6, y: 2)
                }
                .padding(.bottom, 2)

                // 타이틀/서브타이틀
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 6)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 12)
            .padding(.horizontal, 40)
            .onAppear { spin = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title)"))
    }
}


fileprivate struct ConsentNotice: View {
    @Binding var showPrivacy: Bool
    @Binding var showTerms: Bool

    var body: some View {
        VStack(spacing: 2) {

            // 1줄: 링크 포함
            HStack(spacing: 6) {
                Text("회원가입 시")
                    .foregroundColor(AppTheme.textSecondary)
                Button(action: { showPrivacy = true }) {
                    Text("개인정보처리방침")
                        .underline()
                        .foregroundColor(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Text("및")
                    .foregroundColor(AppTheme.textSecondary)

                Button(action: { showTerms = true }) {
                    Text("이용약관")
                        .underline()
                        .foregroundColor(AppTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .lineLimit(1)                 // ← 한 줄로 고정
            .minimumScaleFactor(0.85)     // ← 작은 화면에서 살짝 축소
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            // 2줄: 문장 마무리
            Text("에 동의하신 것으로 간주됩니다.")
                .foregroundColor(AppTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        .font(.system(size: 12.5, weight: .medium)) // ← 살짝 축소
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 22)
    }
}


fileprivate struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("원더미닛 개인정보처리방침").font(.title3.bold())
                    Text("시행일: 2025-08-17").foregroundColor(.secondary)
                }

                SectionHeader("1. 수집하는 정보")
                Bullet("필수: 카카오/애플 계정 식별자, 닉네임, 성별(사용자 설정), 기기 식별자, 로그인 토큰")
                Bullet("선택: 프로필 사진, 관심사, MBTI, 한 줄 소개")
                Bullet("서비스 이용: 통화 매칭·시작·종료 시간, 콜 지속시간, 결제 이력(금액·타임스탬프·영수증 ID), 푸시 토큰")
                Bullet("기술 로그: 앱 버전, OS, 오류/크래시 로그, 네트워크 상태")

                SectionHeader("2. 수집 방법")
                Bullet("사용자 입력(프로필 작성), 앱 사용 중 자동 수집(이벤트), 제3자 로그인(Kakao/Apple).")

                SectionHeader("3. 이용 목적")
                Bullet("1:1 통화 매칭 및 연결(Agora), 계정 인증·보안(Firebase Auth), 결제 및 과금 집계, 품질 개선(오류 분석), 공지·알림 발송(FCM).")

                SectionHeader("4. 제3자 제공/처리위탁")
                Bullet("Firebase(인증·DB·Crashlytics), Firebase Cloud Messaging(푸시), Agora(실시간 음성), Kakao/Apple(소셜 로그인).")
                Text("법령상 요구 또는 이용자 동의 없는 제3자 제공은 하지 않습니다.").foregroundColor(.secondary)

                SectionHeader("5. 보관 기간")
                Bullet("회원 탈퇴 시 지체 없이 파기. 다만 관계 법령에 따른 보존 기간 동안 최소 정보 보관 가능.")
                Bullet("결제/정산 데이터: 관계 법령에 따른 보존 기간 준수.")

                SectionHeader("6. 이용자의 권리")
                Bullet("내 정보 열람·정정·삭제, 처리 정지 요청 가능(앱 내 프로필/문의).")
                Bullet("푸시 수신 동의/철회: OS/앱 설정에서 변경 가능.")

                SectionHeader("7. 아동의 개인정보")
                Bullet("만 14세 미만 이용 불가. 의심 시 계정 제한 및 보호자 동의 확인 요청.")

                SectionHeader("8. 안전성 확보 조치")
                Bullet("HTTPS 전송 암호화, 접근 권한 최소화, 접근 기록 보관, 정기 점검.")
                Bullet("민감정보 비수집, 결제정보는 결제대행/플랫폼에서 처리.")

                SectionHeader("9. 국외 이전")
                Bullet("Firebase/Agora 등 클라우드 서버가 해외에 위치할 수 있음. 법령 준수.")

                SectionHeader("10. 문의처")
                Bullet("이메일: gimyeongdae030818@gmail.com")
                Bullet("주소: (추가 예정)")

                SectionHeader("11. 고지 의무")
                Text("정책 변경 시 앱 공지 또는 이메일로 고지하며, 중대한 변경은 시행 7일 전 고지합니다.")
            }
            .padding(16)
        }
    }
}

fileprivate struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    Text("원더미닛 이용약관").font(.title3.bold())
                    Text("시행일: 2025-08-17").foregroundColor(.secondary)
                }

                SectionHeader("1. 목적")
                Text("본 약관은 원더미닛(이하 ‘회사’)이 제공하는 1:1 음성 통화 매칭 서비스 이용과 관련하여 회사와 이용자 간 권리·의무 및 책임사항을 규정합니다.")

                SectionHeader("2. 계정 및 자격")
                Bullet("만 14세 이상만 이용 가능.")
                Bullet("카카오/애플 소셜 로그인으로 계정 생성, 정보는 정확하게 제공해야 함.")
                Bullet("부정사용·법령 위반 시 계정 제한 또는 해지 가능.")

                SectionHeader("3. 서비스 내용")
                Bullet("실시간 매칭 후 1:1 음성 통화 연결(Agora 기반).")
                Bullet("운영상 변경에 따라 기능 추가/수정/중단될 수 있음.")

                SectionHeader("4. 요금 및 결제")
                Bullet("예시: 기본 10분 700원, 이후 분당 700원(앱 공지에 따라 변경 가능).")
                Bullet("초기 30초 유예, 환불 규정은 스토어 정책 우선.")
                Bullet("과금 시작 조건: 매칭 확정 + 양측 Agora 접속 + T0 이후 10초 생존.")

                SectionHeader("5. 이용자 의무(금지행위)")
                Bullet("사칭, 불법 정보 유통, 성적/혐오/폭력 표현, 광고/스팸, 서비스 방해 금지.")
                Bullet("타인 개인정보 수집/요청/공유 금지.")
                Bullet("동의 없는 통화 녹음·배포 금지(법령 준수).")

                SectionHeader("6. 권리 귀속")
                Bullet("서비스 소프트웨어의 지식재산권은 회사에 귀속.")
                Bullet("이용자 콘텐츠는 이용자에게 귀속하나, 서비스 제공/홍보 범위 내 사용 허용될 수 있음(비독점/무상).")

                SectionHeader("7. 서비스 변경·중단")
                Bullet("개선/안정화를 위해 변경 가능, 중대한 변경은 사전 고지.")
                Bullet("천재지변/제3자 플랫폼 장애 등 불가항력 시 중단 가능.")

                SectionHeader("8. 면책")
                Bullet("이용자 귀책·제3자 장애·불가항력에 대해 회사는 책임 제한.")

                SectionHeader("9. 손해배상")
                Text("고의 또는 중과실 없는 특별·간접손해는 책임 부담하지 않습니다.")

                SectionHeader("10. 해지")
                Bullet("이용자는 ‘계정 삭제’로 탈퇴 가능.")
                Bullet("법령·약관 위반 시 제한 또는 해지(긴급 시 사후 통지).")

                SectionHeader("11. 준거법/관할")
                Bullet("대한민국 법률을 준거법으로 하며, 관할은 회사 소재지 관할 법원.")

                SectionHeader("12. 약관 변경")
                Text("변경 시 앱 공지/이메일 고지, 중대한 변경은 7일 전 고지.")
            }
            .padding(16)
        }
    }
}

fileprivate struct SectionHeader: View {
    let title: String
    init(_ t: String) { self.title = t }
    var body: some View { Text(title).font(.headline) }
}
fileprivate struct Bullet: View {
    let text: String
    init(_ t: String) { self.text = t }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").bold()
            Text(text)
        }
    }
}

private func withAppCheckHeader(_ request: URLRequest,
                                completion: @escaping (URLRequest) -> Void) {
    AppCheck.appCheck().token(forcingRefresh: false) { token, _ in
        var req = request
        if let t = token?.token {
            req.setValue(t, forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        completion(req)
    }
}

// ★ Authorization(ID 토큰) + AppCheck 둘 다 붙이는 도우미
private func withAuthAndAppCheck(_ request: URLRequest,
                                 completion: @escaping (URLRequest) -> Void) {
    var req = request
    // 1) AppCheck
    AppCheck.appCheck().token(forcingRefresh: false) { token, _ in
        if let t = token?.token { req.setValue(t, forHTTPHeaderField: "X-Firebase-AppCheck") }
        // 2) Firebase Auth ID 토큰
        if let user = Auth.auth().currentUser {
            user.getIDToken { idToken, _ in
                if let idToken = idToken {
                    req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
                }
                completion(req)
            }
        } else {
            completion(req)
        }
    }
}

