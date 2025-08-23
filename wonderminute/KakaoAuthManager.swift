import Foundation
import FirebaseAuth
import KakaoSDKAuth
import KakaoSDKUser

class KakaoAuthManager {
    static let shared = KakaoAuthManager()

    private init() {}

    func loginWithKakao(completion: @escaping (Result<Void, Error>) -> Void) {
        // 1. 로그인 시도
        if UserApi.isKakaoTalkLoginAvailable() {
            UserApi.shared.loginWithKakaoTalk { [weak self] (oauthToken, error) in
                if let error = error {
                    print("❌ 카카오톡 로그인 실패: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let token = oauthToken else {
                    print("❌ 카카오톡 토큰 없음")
                    completion(.failure(NSError(domain: "No Kakao token", code: -1)))
                    return
                }

                print("✅ 카카오톡 로그인 성공: \(token.accessToken)")
                self?.authenticateWithFirebase(kakaoAccessToken: token.accessToken, completion: completion)
            }
        } else {
            UserApi.shared.loginWithKakaoAccount { [weak self] (oauthToken, error) in
                if let error = error {
                    print("❌ 카카오 계정 로그인 실패: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                guard let token = oauthToken else {
                    print("❌ 카카오 계정 토큰 없음")
                    completion(.failure(NSError(domain: "No Kakao token", code: -1)))
                    return
                }

                print("✅ 카카오 계정 로그인 성공: \(token.accessToken)")
                self?.authenticateWithFirebase(kakaoAccessToken: token.accessToken, completion: completion)
            }
        }
    }

    private func authenticateWithFirebase(kakaoAccessToken: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // 2. Firebase Functions에 Access Token 전송
        guard let url = URL(string: "https://us-central1-wonderminute-7a4c9.cloudfunctions.net/kakaoLogin") else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ["token": kakaoAccessToken]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Firebase Function 요청 실패: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let data = data else {
                print("❌ 응답 데이터 없음")
                completion(.failure(NSError(domain: "No data", code: -1)))
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let customToken = json?["firebase_token"] as? String {
                    print("✅ 커스텀 토큰 획득 성공")

                    // 3. Firebase Auth 로그인
                    Auth.auth().signIn(withCustomToken: customToken) { result, error in
                        if let error = error {
                            print("❌ Firebase 로그인 실패: \(error.localizedDescription)")
                            completion(.failure(error))
                        } else {
                            print("✅ Firebase 로그인 성공: \(result?.user.uid ?? "Unknown UID")")
                            completion(.success(()))
                        }
                    }
                } else {
                    print("❌ 커스텀 토큰 파싱 실패")
                    completion(.failure(NSError(domain: "No custom token", code: -1)))
                }
            } catch {
                print("❌ JSON 파싱 에러: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }.resume()
    }
}

