import SwiftUI

struct PhoneVerifyView: View {
    @StateObject private var vm = PhoneVerifyVM()
    var onVerified: (_ phoneE164: String) -> Void

    var body: some View {
        ZStack {
            // 배경
            GradientBackground().ignoresSafeArea()

            // 내용 카드
            VStack {
                Spacer(minLength: 28)

                VStack(alignment: .leading, spacing: 18) {

                    // 타이틀 & 서브
                    VStack(alignment: .leading, spacing: 6) {
                        Text("전화번호 인증")
                            .font(.title3.bold())
                            .foregroundColor(.white)

                        Text("본인 확인을 위해 휴대폰 번호를 입력하고\n인증코드를 받아주세요.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.85))
                    }

                    // 전화번호 입력
                    VStack(spacing: 10) {
                        GlassField(
                            title: "휴대폰 번호",
                            placeholder: "예: 01012345678",
                            text: $vm.rawPhone,
                            keyboard: .numberPad
                        )

                        Button(action: { vm.sendCode() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text(vm.isSending ? "전송 중…" : "인증코드 받기")
                                    .font(.callout.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(GlassPrimaryButtonStyle(disabled: vm.isSending || vm.rawPhone.isEmpty))
                        .disabled(vm.isSending || vm.rawPhone.isEmpty)
                    }

                    // 인증코드 입력
                    VStack(spacing: 10) {
                        GlassField(
                            title: "인증코드",
                            placeholder: "6자리 숫자",
                            text: $vm.code,
                            keyboard: .numberPad
                        )

                        Button(action: {
                            vm.confirmCode { phone in
                                onVerified(phone)
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text(vm.isVerifying ? "확인 중…" : "확인")
                                    .font(.callout.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(GlassPrimaryButtonStyle(disabled: vm.isVerifying || vm.code.count < 6))
                        .disabled(vm.isVerifying || vm.code.count < 6)
                    }

                    // 에러 메시지
                    if let e = vm.error, !e.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.bold))
                            Text(e)
                                .font(.footnote)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .foregroundColor(.red.opacity(0.95))
                        .padding(.top, 4)
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 18, y: 12)
                .padding(.horizontal, 20)

                Spacer()
            }

            // 로딩 오버레이 (LoginView 톤과 맞춤)
            if vm.isSending || vm.isVerifying {
                LoadingOverlayPV(
                    title: vm.isSending ? "인증코드 전송 중…" : "코드 확인 중…",
                    subtitle: vm.isSending
                    ? "통신사/네트워크 상태에 따라 최대 수십 초 걸릴 수 있어요"
                    : "인증 정보를 확인하고 있어요"
                )
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Subviews & Styles (이 파일 전용)

// 글래스 텍스트필드
fileprivate struct GlassField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))

            ZStack(alignment: .leading) {
                // placeholder
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 12)
                }
                TextField("", text: $text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
            }
            .frame(height: 44)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
    }
}

// 글래스 프라이머리 버튼 스타일
fileprivate struct GlassPrimaryButtonStyle: ButtonStyle {
    var disabled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(disabled ? Color.white.opacity(0.14) : Color.white.opacity(configuration.isPressed ? 0.18 : 0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// 로딩 오버레이 (LoginView의 LoadingOverlay와 충돌 없도록 이름 분리)
fileprivate struct LoadingOverlayPV: View {
    let title: String
    let subtitle: String?

    @State private var spin = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.09))
                        .frame(width: 74, height: 74)

                    Circle()
                        .trim(from: 0.08, to: 0.92)
                        .stroke(style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(width: 74, height: 74)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.05).repeatForever(autoreverses: false), value: spin)

                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .shadow(color: .white.opacity(0.25), radius: 6, y: 2)
                }
                .padding(.bottom, 2)

                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
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
