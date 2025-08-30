import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import AVFAudio


private let contentMaxW: CGFloat = 360   // iPhone에서 보기 좋은 폭


struct CallView: View {
    // ⬇️ 추가: 부모(MainTabView)에서 주입
    @EnvironmentObject var appState: AppState
       @ObservedObject var call: CallEngine
       @ObservedObject var watcher: MatchWatcher
    @State private var isMatching: Bool = false
    @State private var selectedPref: String = "all" // "all" | "남자" | "여자"

    var body: some View {
        NavigationView {
            ZStack {
                // 기존 ZStack 교체
                GradientBackground()
                    .ignoresSafeArea()

                VStack(spacing: 28) {                       // ⬅️ 빠져있던 VStack 복구
                    Spacer(minLength: 24)
                    
                    // ① 아이콘 타일 – 더 얇게, 깔끔하게
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 92, height: 92)
                            .shadow(color: .black.opacity(0.08), radius: 14, y: 8)   // ↓ 낮춤
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.black.opacity(0.05), lineWidth: 0.5) // ↓ 얇게
                            )
                        Image("AppLogo")
                            .resizable().renderingMode(.original).scaledToFit()
                            .frame(width: 56, height: 56)
                    }
                    .padding(.top, 8)

                    
                    // 성별 카드
                    VStack(alignment: .leading, spacing: 12) {
                        Text("원하는 상대")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(hex: 0x1B2240).opacity(0.9))

                        GenderSegmented(selection: $selectedPref)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                    .softElevatedCard(corner: 22)
                    // ❌ 기존: .padding(.horizontal, 10)
                    .frame(maxWidth: contentMaxW)           // ✅ 폭 고정
                    .padding(.horizontal, 16)               // ✅ 여백 통일

                    
                    // ⬇️ 성별 카드(.softElevatedCard) 바로 아래에 추가
                    ValuePropsRow()
                        .frame(maxWidth: contentMaxW, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    
                    
                    // ⬇️ ValuePropsRow() 바로 아래에 추가
                    DailyPromptCard()
                        .frame(maxWidth: contentMaxW)
                        .padding(.horizontal, 16)

                    
                  
                    
                    // CTA 버튼
                    Button(action: {
                        appState.userRequestedMatching = true
                        requestMicPermission { granted in
                            guard granted else { return }
                            // ⬇️ 매칭 시작 전에, 내가 차단한 UID 목록을 큐에 퍼블리시
                            SafetyCenter.shared.publishExclusionsForMatching { _ in
                                if call.currentRoomId == nil {
                                    savePreferenceThenGo()
                                } else {
                                    isMatching = false
                                }
                            }
                        }
                    })
 {
                        Text("통화 시작하기")
                    }
                    .buttonStyle(CallCTAPillStyle())
                    .frame(maxWidth: contentMaxW)
                    .padding(.horizontal, 16)

                    
                    NavigationLink(
                        destination: MatchingView(call: call, watcher: watcher),
                        isActive: $isMatching
                    ) { EmptyView() }

                    
                    Text("원더미닛 런칭 · 지금 첫 통화를 만들어주세요")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 4)
                        .frame(maxWidth: contentMaxW)
                    
                    Spacer(minLength: 28)
                } // <- VStack 닫힘 (중요!)
            }
            
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 가운데 타이틀은 숨김
                ToolbarItem(placement: .principal) { EmptyView() }

                // 오른쪽 상단 아이템들: [미닛(아이콘+0)] [상점] [알람]
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    MinuteBadgeView()  // ✅ 인자 제거    // ← 작은 앱 아이콘 + 0

                    Button(action: {
                        // 아직 기능 없음 (상점)
                    }) {
                        Image(systemName: "bag.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                    }

                    Button(action: {
                        // 아직 기능 없음 (알람)
                    }) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.leading, 2)
                            .contentShape(Rectangle())
                    }
                }
            }

        }
              // ✅ 통화 종료 브로드캐스트 수신 시 매칭 화면 닫기
              .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WonderMinute.NavigateToCall"))) { _ in
                  isMatching = false
              }
              // ✅ 방이 생성되면 MatchingView는 의미 없으니 닫기
              .onChange(of: call.currentRoomId) { rid in
                  if rid != nil { isMatching = false }
              }
              // ✅ 화면 복귀 시에도 초기화(재진입 방지)
              .onAppear {
                  isMatching = false
              }
              .accentColor(.white)
          }

    // ✅ 기존 기능 유지
    private func savePreferenceThenGo() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isMatching = true
            return
        }
        let db = Firestore.firestore()
        db.collection("users").document(uid)
            .setData(["wantGenderPreference": selectedPref], merge: true) { _ in
                self.isMatching = true
            }
    }
}

// MARK: - Subviews

/// 그라데이션 아이콘 로고 (상단)

private struct GradientIcon: View {        // ✅ 단일 선언만 유지
    let symbol: String
    let size: CGFloat

    var body: some View {
        let available = UIImage(systemName: symbol) != nil
        let finalSymbol = available ? symbol : "phone.fill"   // 폴백

        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x8B5CFF), Color(hex: 0x4E73FF)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size + 24, height: size + 24)
                .shadow(color: .black.opacity(0.20), radius: 12, x: 0, y: 6)

            Image(systemName: finalSymbol)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .frame(width: size, height: size)
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
        }
        .accessibilityLabel("전화 매칭 시작")
    }
}


/// 성별 상징 일러스트 (장식용)
private struct GenderIllustration: View {
    var body: some View {
        HStack(spacing: -16) {
            IllustrationBubble(icon: "person.fill", start: 0x7C4DFF, end: 0x5A6AFF, size: 52)
                .offset(y: 4)
            IllustrationBubble(icon: "figure.dress", start: 0x5A6AFF, end: 0x33B6FF, size: 64)
            IllustrationBubble(icon: "person.3.fill", start: 0x8B5CFF, end: 0x4E73FF, size: 52)
                .offset(y: 6)
        }
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }
}

private struct IllustrationBubble: View {
    let icon: String
    let start: UInt
    let end: UInt
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: start), Color(hex: end)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)

            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.52, height: size * 0.52)
                .foregroundColor(.white)
        }
    }
}

private struct MinuteBadgeView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("WMPhoneDot")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundColor(.white)
            Text("0")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("미닛 0")
    }
}


// ③ 세그먼트(비선택은 더 플랫, 선택은 선명)
private struct SegItem: View {
    let imageName: String
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(imageName)
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(height: 16)
                .foregroundColor(isSelected ? Color(hex: 0x5A6AFF) : Color(hex: 0x8A8F98)) // 살짝 진하게

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(isSelected ? Color(hex: 0x1B2240) : Color(hex: 0x8A8F98))
                .lineLimit(1).minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(isSelected ? 1.0 : 0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color(hex: 0x5A6AFF).opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.08 : 0.03), radius: isSelected ? 8 : 4, y: 3)
    }
}



private struct GenderSegmented: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            Button { selection = "all" } label: {
                SegItem(imageName: "GenderAll",
                        title: "모든 성별",
                        isSelected: selection == "all")
            }
            .buttonStyle(.plain)

            Button { selection = "남자" } label: {
                SegItem(imageName: "GenderMale",
                        title: "남자만",
                        isSelected: selection == "남자")
            }
            .buttonStyle(.plain)

            Button { selection = "여자" } label: {
                SegItem(imageName: "GenderFemale",
                        title: "여자만",
                        isSelected: selection == "여자")
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        // 컨테이너는 투명 — 이미 바깥 카드가 흰색이라 중첩 화이트를 줄여줌
    }
}


// MARK: - Style Helpers

private struct GlassCard: ViewModifier {
    var corner: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                // 바깥 라인
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
            // 안쪽 은은한 하이라이트
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.05)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, y: 10) // 배경과 분리
    }
}

private extension View {
    func glassCard(corner: CGFloat = 20) -> some View { modifier(GlassCard(corner: corner)) }
}

private struct ElevatedCTA: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.30), radius: 20, y: 12)
            .overlay( // 버튼 주변 링
                Capsule()
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            )
    }
}
private extension View { func elevatedCTA() -> some View { modifier(ElevatedCTA()) } }

// MARK: - Depth helpers
// ② 성별 카드 – 현재 그대로 두되 SoftElevatedCard를 가볍게
// 기존 SoftElevatedCard 수정(덮어쓰기)
private struct SoftElevatedCard: ViewModifier {
    var corner: CGFloat = 20          // ← 22 → 20
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.08), radius: 14, y: 8) // ↓
            .shadow(color: .black.opacity(0.03), radius: 6, y: 2)  // ↓
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.40), lineWidth: 0.5) // ↓ 얇게
            )
    }
}

private extension View {
    func softElevatedCard(corner: CGFloat = 22) -> some View {
        modifier(SoftElevatedCard(corner: corner))
    }
}

// MARK: - Solid primary button
// ④ CTA – 링 제거, 그림자는 단일로 선명하게
private struct SolidPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [Color(hex: 0x5A6AFF), Color(hex: 0x7A5CFF)],
                               startPoint: .leading, endPoint: .trailing) // 방향도 좌→우로 통일
            )
            .clipShape(Capsule())
            .shadow(color: .black.opacity(configuration.isPressed ? 0.06 : 0.10),
                    radius: configuration.isPressed ? 6 : 12, y: configuration.isPressed ? 3 : 8) // 단일
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

// 파일 하단에 추가
fileprivate struct AmbientBackground: View {
    var body: some View {
        ZStack {
            // 좌상단 보라 블롭
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x8B5CFF), Color(hex: 0x6E7BFF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 360, height: 360)
                .blur(radius: 120)
                .opacity(0.35)
                .offset(x: -140, y: -160)

            // 우상단 블루 블롭
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x4E73FF), Color(hex: 0x33B6FF)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 300, height: 300)
                .blur(radius: 110)
                .opacity(0.30)
                .offset(x: 130, y: -130)

            // CTA 위 그라데이션 물결(아래 허전한 부분 채움)
            Ellipse()
                .fill(LinearGradient(colors: [Color.white.opacity(0.28), .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 520, height: 280)
                .blur(radius: 80)
                .opacity(0.22)
                .offset(y: 120)
        }
        .compositingGroup()
        .blendMode(.plusLighter)
    }
}

// 파일 하단에 교체
// 한 줄 고정 배지 행
fileprivate struct ValuePropsRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ValueTag(icon: "lock.shield.fill", text: "안전한 익명 통화")
            ValueTag(icon: "bolt.badge.a.fill", text: "실시간 매칭")
            ValueTag(icon: "hand.raised.fill", text: "신고/차단 지원")
        }
        .frame(maxWidth: .infinity, alignment: .center) // ✅ 가운데 정렬
    }
}


// 컴팩트 칩
fileprivate struct ValueTag: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))

            Text(text)
                .font(.system(size: 11, weight: .semibold)) // ⬅️ 살짝 축소
                .lineLimit(1)
                .minimumScaleFactor(0.75)                   // ⬅️ 필요시 더 줄여서 한 줄 유지
                .allowsTightening(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.8)
        )
        .foregroundColor(.white.opacity(0.95))
        .fixedSize(horizontal: true, vertical: true) // ⬅️ 내부에서만 크기 결정(늘어남 방지)
    }
}


// 파일 하단에 추가
// 파일 하단 교체
fileprivate struct DailyPromptCard: View {
    @State private var idx = 0
    // ✅ 요청하신 3개의 멘트
    private let prompts = [
        "늘 상대방에게 따뜻하게 말해주세요^^",
        "상대방 말을 경청해주세요~",
        "이유 없이 폭언을 하거나 시비를 거는 행위는 자제해주세요 🙂"
    ]

    // 자동 회전 타이머 (4.5초)
    private let timer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 12) {
            // 아이콘 뱃지
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .bold))
                .padding(8)
                .background(Color(hex: 0xEEF1F6), in: Circle())
                .foregroundColor(Color(hex: 0x5A6AFF))

            // 회전 멘트
            Text(prompts[idx])
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Color(hex: 0x1B2240))
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            Spacer()

            // 수동 새로고침
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    idx = (idx + 1) % prompts.count
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(8)
                    .background(Color(hex: 0xEEF1F6), in: Circle())
                    .foregroundColor(Color(hex: 0x1B2240))
            }
            .buttonStyle(.plain)
        }
        .lightCard(corner: 16)                // 성별 카드와 톤 맞춤 (화이트 카드)
        .frame(maxWidth: contentMaxW)
        .padding(.horizontal, 16)
        .onReceive(timer) { _ in              // ⏱ 자동 회전
            withAnimation(.easeOut(duration: 0.2)) {
                idx = (idx + 1) % prompts.count
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("안내 멘트")
        .accessibilityValue(prompts[idx])
    }
}



fileprivate struct TopGlowOverlay: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .white.opacity(0.14), location: 0.00),
                .init(color: .white.opacity(0.08), location: 0.22),
                .init(color: .white.opacity(0.02), location: 0.45),
                .init(color: .clear,                location: 0.70) // 중앙보다 아래로
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// 성별 카드와 동일 톤의 라이트 카드
private struct LightCard: ViewModifier {
    var corner: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
    }
}
private extension View { func lightCard(corner: CGFloat = 16) -> some View { modifier(LightCard(corner: corner)) } }

struct FlowLayout<Content: View>: View {
    let alignment: HorizontalAlignment
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(alignment: HorizontalAlignment = .leading,
         spacing: CGFloat = 8,
         @ViewBuilder content: @escaping () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        _FlowLayout(alignment: alignment, spacing: spacing) { content() }
    }
}

struct _FlowLayout: Layout {
    let alignment: HorizontalAlignment
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0; y += rowH + spacing; rowH = 0
            }
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.width {
                x = 0; y += rowH + spacing; rowH = 0
            }
            s.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            rowH = max(rowH, size.height)
            x += size.width + spacing
        }
    }
}

// 메인 탭바의 on 상태와 동일한 톤의 CTA 스타일
private struct CallCTAPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(colors: [AppTheme.purple, AppTheme.blue],
                               startPoint: .leading, endPoint: .trailing) // 🔹 TabPill과 동일
            )
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.15), lineWidth: 1) // 🔹 TabPill의 stroke 톤
            )
            .shadow(color: .black.opacity(configuration.isPressed ? 0.06 : 0.12),
                    radius: configuration.isPressed ? 6 : 12, y: configuration.isPressed ? 3 : 8)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.9), value: configuration.isPressed)
    }
}

private func requestMicPermission(completion: @escaping (Bool)->Void) {
    let session = AVAudioSession.sharedInstance()
    // iOS 전체에서 공통 사용 가능
    session.requestRecordPermission { granted in
        DispatchQueue.main.async { completion(granted) }
    }
}
