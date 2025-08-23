import SwiftUI

struct PhoneVerifyView: View {
    @StateObject private var vm = PhoneVerifyVM()
    var onVerified: (_ phoneE164: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("전화번호 인증").font(.title3).bold()

            TextField("예: 01012345678", text: $vm.rawPhone)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            Button {
                vm.sendCode()
            } label: {
                Text(vm.isSending ? "전송 중..." : "인증코드 받기")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isSending || vm.rawPhone.isEmpty)

            TextField("인증코드 6자리", text: $vm.code)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)

            Button {
                vm.confirmCode { phone in
                    onVerified(phone)
                }
            } label: {
                Text(vm.isVerifying ? "확인 중..." : "확인")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isVerifying || vm.code.count < 6)

            if let e = vm.error {
                Text(e).foregroundColor(.red).font(.footnote)
            }
        }
    }
}
