import Foundation
import FirebaseAuth
import CryptoKit

final class PhoneVerifyVM: ObservableObject {
    @Published var rawPhone: String = ""  // 예: 01012345678
    @Published var code: String = ""      // 6자리
    @Published var isSending = false
    @Published var isVerifying = false
    @Published var error: String?
    private var verificationID: String?

    // KR 번호를 E.164(+82)로 변환
    func e164KR(_ input: String) -> String {
        let d = input.filter(\.isNumber)
        if d.hasPrefix("0") { return "+82" + String(d.dropFirst()) }
        if d.hasPrefix("82") { return "+" + d }
        if d.hasPrefix("+")  { return d }
        return "+82" + d
    }

    func sendCode() {
        error = nil
        isSending = true
        let phone = e164KR(rawPhone)
        PhoneAuthProvider.provider().verifyPhoneNumber(phone, uiDelegate: nil) { [weak self] vid, err in
            DispatchQueue.main.async {
                self?.isSending = false
                if let err = err { self?.error = err.localizedDescription; return }
                self?.verificationID = vid
            }
        }
    }

    func confirmCode(onLinked: @escaping (_ phoneE164: String) -> Void) {
        guard let vid = verificationID else { error = "먼저 인증코드를 요청하세요."; return }
        isVerifying = true
        let phone = e164KR(rawPhone)
        let cred = PhoneAuthProvider.provider().credential(withVerificationID: vid, verificationCode: code)

        if let user = Auth.auth().currentUser {
            user.link(with: cred) { _, err in
                DispatchQueue.main.async {
                    self.isVerifying = false
                    if let err = err { self.error = err.localizedDescription; return }
                    onLinked(phone)
                }
            }
        } else {
            Auth.auth().signIn(with: cred) { _, err in
                DispatchQueue.main.async {
                    self.isVerifying = false
                    if let err = err { self.error = err.localizedDescription; return }
                    onLinked(phone)
                }
            }
        }
    }

    // (선택) 해시 보관 시 사용
    func sha256(_ text: String) -> String {
        let data = Data(text.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
