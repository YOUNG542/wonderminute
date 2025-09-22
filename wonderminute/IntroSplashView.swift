import SwiftUI

struct IntroSplashView: View {
    @EnvironmentObject var appState: AppState

    // MARK: - Warm Theme (이 파일 전용 로컬 팔레트)
    private struct WarmTheme {
        static let ivory      = Color(red: 1.00, green: 0.98, blue: 0.96) // 아주 연한 아이보리
        static let cream      = Color(red: 1.00, green: 0.96, blue: 0.93) // 배경 그라데이션 하단
        static let pink       = Color(red: 1.00, green: 0.80, blue: 0.84) // 부드러운 핑크
        static let peach      = Color(red: 1.00, green: 0.86, blue: 0.70) // 피치
        static let apricot    = Color(red: 1.00, green: 0.74, blue: 0.55) // 살구
        static let coral      = Color(red: 0.98, green: 0.53, blue: 0.47) // 코랄(포인트)
        static let textMain   = Color(red: 0.24, green: 0.20, blue: 0.19) // 따뜻한 다크 브라운
        static let cardStroke = Color.black.opacity(0.06)
        static let cardShadow = Color.black.opacity(0.16)
    }

    // MARK: - Drop (물방울)
    @State private var dropOffset: CGFloat = -260
    @State private var dropScale: CGFloat = 0.6
    @State private var dropBlur: CGFloat = 6
    @State private var dropOpacity: Double = 1.0

    // MARK: - Ripple (물결 2겹)
    @State private var showRipple1 = false
    @State private var showRipple2 = false
    @State private var ripple1Scale: CGFloat = 0.2
    @State private var ripple2Scale: CGFloat = 0.2
    @State private var ripple1Opacity: Double = 0.7
    @State private var ripple2Opacity: Double = 0.55
    @State private var showCopy = false

    // MARK: - Logo
    @State private var logoScale: CGFloat = 0.86
    @State private var logoOpacity: Double = 0.0
    @State private var glow = false   // ✨ 글로우 애니메이션

    private let appLogoName = "AppLogo"

    var body: some View {
        ZStack {
            // 기존 GradientBackground() → 따뜻한 배경 그라데이션으로 교체
            LinearGradient(
                colors: [WarmTheme.ivory, WarmTheme.cream],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                Spacer()

                ZStack {
                    // Ripple (색도 화이트 대신 아이보리 톤으로 살짝 따뜻하게)
                    Group {
                        Circle()
                            .stroke(WarmTheme.ivory.opacity(0.70), lineWidth: 2)
                            .frame(width: 220, height: 220)
                            .scaleEffect(ripple1Scale)
                            .opacity(showRipple1 ? ripple1Opacity : 0)
                            .compositingGroup()
                            .blendMode(.screen)
                            .animation(.easeOut(duration: 0.65), value: showRipple1)
                            .animation(.easeOut(duration: 0.85), value: ripple1Scale)

                        Circle()
                            .stroke(WarmTheme.ivory.opacity(0.50), lineWidth: 2)
                            .frame(width: 280, height: 280)
                            .scaleEffect(ripple2Scale)
                            .opacity(showRipple2 ? ripple2Opacity : 0)
                            .compositingGroup()
                            .blendMode(.screen)
                            .animation(.easeOut(duration: 0.8), value: showRipple2)
                            .animation(.easeOut(duration: 1.0), value: ripple2Scale)
                    }
                    .drawingGroup()

                    // Drop (물방울) : 보라/블루 → 핑크/피치 그라데이션
                    Circle()
                        .fill(
                            LinearGradient(colors: [WarmTheme.pink, WarmTheme.peach],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 64, height: 64)
                        .scaleEffect(x: 1.06, y: 1.0)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 20, height: 20)
                                .offset(x: -10, y: -12)
                        )
                        .scaleEffect(dropScale)
                        .offset(y: dropOffset)
                        .blur(radius: dropBlur)
                        .shadow(color: WarmTheme.cardShadow, radius: 12, x: 0, y: 8)
                        .opacity(dropOpacity)

                    // 최신 톤 아이콘 카드 + 글로우 링 (아래에서 스타일 변경)
                    AppIconCard(logoName: appLogoName, cardSize: 124, logoSize: 82, corner: 24, glow: glow)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .accessibilityLabel("WonderMinute App Icon")
                }
                .frame(height: 320)

                // IntroSplashView 내부
                TypingSequenceText(
                    messages: [
                        "때로는 누군가가 아무 말 없이 들어줬으면 하는거죠?....",
                        "각박한 세상에 그런 사람을 만나기 쉽지 않아요..",
                        "같은 마음의 누군가에게 전하면, 따뜻한 위로가 돌아올 겁니다."
                    ]
                ) {
                    // ✅ 모든 문구 끝난 뒤 화면 전환
                    withAnimation(.easeInOut(duration: 0.6)) {
                        appState.setView(.welcome, reason: "splash finished")
                    }
                }

                
                Spacer()
            }
        }
        .onAppear { runAnimation() }
    }

    // MARK: - Animation (동작 동일)
    private func runAnimation() {
        withAnimation(.interactiveSpring(response: 0.55, dampingFraction: 0.72, blendDuration: 0.12)) {
            dropOffset = 0
            dropScale = 1.0
            dropBlur = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            showRipple1 = true
            ripple1Scale = 1.15
            ripple1Opacity = 0.0

            withAnimation(.easeOut(duration: 0.25)) {
                dropOpacity = 0.0
                dropScale = 0.92
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                showRipple2 = true
                ripple2Scale = 1.25
                ripple2Opacity = 0.0
            }

            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                logoOpacity = 1.0
                logoScale = 1.0
            }
            glow = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 80) {
            withAnimation(.easeInOut(duration: 30)) {
                appState.setView(.welcome, reason: "splash finished")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            showCopy = true
        }

    }
}

// 여러 문구를 순차적으로 타이핑/삭제하는 컴포넌트 (느긋한 버전)
struct TypingSequenceText: View {
    let messages: [String]
    let onFinished: () -> Void

    // ⏱ 타이밍 파라미터들 — 필요하면 숫자만 조절!
    var delayBeforeStart: Double = 1.4      // 로고 후 첫 시작 대기
    var wrapLimit: Int = 18                 // 긴 문장 자동 줄바꿈 기준
    var appearDelayPerChar: Double = 0.05   // 글자 등장 간격 (↑ 느리게)
    var pauseAfterShown: Double = 1.5       // 모두 보인 뒤 멈춤 시간
    var eraseDelayPerChar: Double = 0.04   // 글자 사라짐 간격 (↑ 느리게)
    var pauseAfterErased: Double = 1.0      // 완전히 0자가 된 뒤 다음 문장까지 대기

    @State private var currentIndex = 0
    @State private var visibleCount = 0
    @State private var isErasing = false

    var body: some View {
        let wrapped = softWrap(messages[currentIndex], limit: wrapLimit)
        let lines = wrapped.split(separator: "\n", omittingEmptySubsequences: false)

        VStack(spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { lineIndex, line in
                HStack(spacing: 0) {
                    ForEach(Array(line.enumerated()), id: \.offset) { charIndex, char in
                        let absIndex = absoluteIndex(in: lines, line: lineIndex, char: charIndex)
                        Text(String(char))
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.24, green: 0.20, blue: 0.19))
                            .opacity(absIndex < visibleCount ? 1 : 0)
                            .offset(y: absIndex < visibleCount ? 0 : 8)
                            .animation(
                                .easeOut(duration: 0.55).delay(Double(absIndex) * appearDelayPerChar),
                                value: visibleCount
                            )
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delayBeforeStart) {
                startTyping(wrappedText: wrapped)
            }
        }
        .onChange(of: currentIndex) { _ in
            let nextWrapped = softWrap(messages[currentIndex], limit: wrapLimit)
            startTyping(wrappedText: nextWrapped)
        }
    }

    private func absoluteIndex(in lines: [Substring], line: Int, char: Int) -> Int {
        var count = 0
        if line > 0 { for i in 0..<line { count += lines[i].count } }
        return count + char
    }

    private func startTyping(wrappedText: String) {
        isErasing = false
        visibleCount = 0
        let charCount = wrappedText.replacingOccurrences(of: "\n", with: "").count

        // 한 글자씩 나타남
        for i in 0..<charCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * appearDelayPerChar) {
                guard !isErasing else { return }
                visibleCount = i + 1
            }
        }

        // 모두 표시 후 충분히 멈춤
        let showDuration = Double(charCount) * appearDelayPerChar + pauseAfterShown
        DispatchQueue.main.asyncAfter(deadline: .now() + showDuration) {
            eraseText(charCount: charCount)
        }
    }

    private func eraseText(charCount: Int) {
        isErasing = true

        // 한 글자씩 사라짐
        for i in 0..<charCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * eraseDelayPerChar) {
                visibleCount = charCount - i - 1
            }
        }

        // ✅ 완전히 0자가 된 뒤 충분히 대기하고 다음 문장 시작
        let eraseDuration = Double(charCount) * eraseDelayPerChar
        DispatchQueue.main.asyncAfter(deadline: .now() + eraseDuration + pauseAfterErased) {
            if currentIndex < messages.count - 1 {
                currentIndex += 1
            } else {
                onFinished()
            }
        }
    }

    // 아주 단순한 soft-wrap: limit 글자마다 줄바꿈(가능하면 공백에서 줄바꿈)
    private func softWrap(_ text: String, limit: Int) -> String {
        var result = ""
        var lineCount = 0
        var lastSpacePosInLine: Int? = nil

        for ch in text {
            if ch == "\n" {
                result.append("\n"); lineCount = 0; lastSpacePosInLine = nil
                continue
            }
            result.append(ch)
            lineCount += 1
            if ch == " " { lastSpacePosInLine = result.count }

            if lineCount >= limit {
                if let spacePos = lastSpacePosInLine {
                    let idx = result.index(result.startIndex, offsetBy: spacePos - 1)
                    result.replaceSubrange(idx...idx, with: "\n") // 공백을 줄바꿈으로
                } else {
                    result.append("\n")
                }
                lineCount = 0
                lastSpacePosInLine = nil
            }
        }
        return result
    }
}






// 재사용 가능한 아이콘 카드 컴포넌트 (따뜻한 아이보리 카드 + 은은한 글로우 링)
struct AppIconCard: View {
    let logoName: String
    let cardSize: CGFloat
    let logoSize: CGFloat
    let corner: CGFloat
    var glow: Bool = false

    private struct WarmTheme {
        static let cardFill   = Color(red: 1.00, green: 0.99, blue: 0.97) // 미세하게 따뜻한 화이트
        static let cardStroke = Color.black.opacity(0.06)
        static let cardShadow = Color.black.opacity(0.16)
        static let pink       = Color(red: 1.00, green: 0.80, blue: 0.84)
        static let peach      = Color(red: 1.00, green: 0.86, blue: 0.70)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(WarmTheme.cardFill)
                .frame(width: cardSize, height: cardSize)
                .shadow(color: WarmTheme.cardShadow, radius: 14, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(WarmTheme.cardStroke, lineWidth: 0.8)
                )

            Image(logoName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)

            // 글로우 링: 화이트→핑크/피치 방향으로 은은한 톤
            RoundedRectangle(cornerRadius: corner + 4, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [
                        Color.white.opacity(0.7),
                        WarmTheme.pink.opacity(0.35),
                        WarmTheme.peach.opacity(0.0)
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

