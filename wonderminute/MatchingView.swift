import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// ⬇️ QueueHeartbeat 그대로 (변경 없음)
final class QueueHeartbeat {
    private var timer: Timer?
    private let uid: String
    private let db = Firestore.firestore()

    init(uid: String) { self.uid = uid }

    func start() {
        stop()
        sendBeat() // 즉시 1회
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.sendBeat()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sendBeat() {
        db.collection("matchingQueue").document(uid).setData([
            "heartbeatAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
}

// ⬇️ 여기부터 UI만 변경 (기능 로직 동일)
struct MatchingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @ObservedObject var call: CallEngine
    @ObservedObject var watcher: MatchWatcher
    init(call: CallEngine, watcher: MatchWatcher) {
        self.call = call
        self.watcher = watcher
    }

    @StateObject private var matchingManager = MatchingManager()
    @State private var isMatched = false
    @State private var isCancelling = false
    @State private var message: String?
    @State private var qhb: QueueHeartbeat?

    // ✅ 중복 실행 방지
    @State private var started = false

    // 애니메이션 상태 (UI만)
    @State private var appear = false
    @State private var pulse = false
    @State private var spin  = false

    var body: some View {
        ZStack {
            // ✅ WelcomeView와 동일 톤의 배경
            GradientBackground()   // ✅ 프로젝트 공통 배경 컴포넌트 사용


            VStack(spacing: 20) {
                Spacer(minLength: 24)

                // 헤더 카드
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [Color(hex: 0xFF6B8A), Color(hex: 0xFFB36A)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 86, height: 86)
                            .shadow(color: Color(hex: 0xFF6B8A).opacity(0.28), radius: 18, y: 8)
                            .shadow(color: Color(hex: 0xFFB36A).opacity(0.22), radius: 12, y: 4)


                        Image(systemName: "sparkles")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .scaleEffect(pulse ? 1.08 : 1.0)
                            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
                    }

                    // 제목 (웜 그라데이션 + 여유 패딩으로 잘림 방지)
                    Text("매칭을 찾는 중이에요")
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.vertical, 4)
                        .foregroundColor(.clear)
                        .overlay(
                            LinearGradient(colors: [Color(hex: 0xFF6B8A), Color(hex: 0xFFB36A)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .mask(
                            Text("매칭을 찾는 중이에요")
                                .font(.system(size: 22, weight: .semibold))
                                .padding(.vertical, 4)
                        )

                    // 서브텍스트 (반투명 배경 카드로 어떤 배경에서도 선명)
                    Text(appState.isReadyForQueue ? "잠시만 기다려 주세요. 가장 잘 맞는 상대를 찾고 있어요." : "초기화 중…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: 0x1B2240).opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.92))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )

                }

                .padding(.top, 6)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 8)
                .animation(.easeOut(duration: 0.28), value: appear)

                ZStack {
                    // 바깥 링
                    Circle()
                        .strokeBorder(
                            LinearGradient(colors: [Color(hex: 0xFF6B8A).opacity(0.55),
                                                    Color(hex: 0xFFB36A).opacity(0.55)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 6
                        )
                        .frame(width: 124, height: 124)
                        .shadow(color: Color.black.opacity(0.10), radius: 6, y: 3)

                    // 중앙 숨쉬는 점
                    Circle()
                        .fill(Color.white.opacity(0.70))
                        .frame(width: 10, height: 10)
                        .scaleEffect(pulse ? 1.35 : 0.85)
                        .animation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true), value: pulse)

                    // 링을 따라 도는 작은 점 (로딩 느낌을 명확히)
                    Circle()
                        .fill(Color(hex: 0xFF6B8A))
                        .frame(width: 10, height: 10)
                        .shadow(color: Color(hex: 0xFF6B8A).opacity(0.35), radius: 3, y: 1)
                        .offset(y: -62) // 링 반지름(124/2)만큼 위로
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: spin)
                }




                .padding(.top, 6)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.05), value: appear)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 2)
                }

                // 취소 버튼
                Button {
                    cancelMatchViaFunction()
                } label: {
                    Text(isCancelling ? "취소 중..." : "매칭 취소")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    WarmPillButtonStyle() // 기존 CTA 톤 재사용 → 웜보이스 일관성
                )
                .opacity(isCancelling ? 0.6 : 1)
                      // ✅ 새 스타일 적용
                .disabled(isCancelling)
                .padding(.horizontal, 24)

                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.28).delay(0.1), value: appear)

                // 안내 배너들
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: 0xFFA86A)) // 웜 오렌지
                        Text("매칭 중 앱을 백그라운드로 보내면 매칭이 지연되거나 취소될 수 있어요.")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(Color(hex: 0x1B2240).opacity(0.9)) // 진한 본문색
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white) // 완전 가독
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(colors: [Color(hex: 0xFF6B8A).opacity(0.35),
                                                        Color(hex: 0xFFB36A).opacity(0.35)],
                                               startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)


                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: 0xFF6B8A)) // 웜 로즈
                        Text("안전한 이용을 위해 **개인 연락처 공유, 금전 요구·제안, 외부 링크 유도**는 금지됩니다.")
                            .font(.footnote.weight(.medium))
                            .foregroundColor(Color(hex: 0x1B2240).opacity(0.9))
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(colors: [Color(hex: 0xFF6B8A).opacity(0.35),
                                                        Color(hex: 0xFFB36A).opacity(0.35)],
                                               startPoint: .leading, endPoint: .trailing),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.06), radius: 5, y: 2)

                }
                .padding(.horizontal, 20)

                .padding(.horizontal, 20)
                .padding(.top, 6)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.28).delay(0.12), value: appear)

                Spacer(minLength: 24)

                // 네비게이션 (기존 그대로)
                NavigationLink(
                    destination: MatchedView(call: call, watcher: watcher),
                    isActive: $isMatched
                ) { EmptyView() }
            }

            // 취소 중 오버레이 (기존 동일)
            if isCancelling {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView()
            }
        }
        .onAppear {
            appear = true
            spin = true   // ⬅️ 회전 시작
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
            tryStartMatchingIfReady()
        }

        .onChange(of: isMatched) { matched in
            if matched { qhb?.stop(); qhb = nil }
        }
        .onChange(of: appState.isReadyForQueue) { _ in
            tryStartMatchingIfReady()
        }
        .onDisappear {
            matchingManager.stop()
            qhb?.stop()
            qhb = nil
            started = false
        }
    }

    // MARK: - 서버 함수로 취소 (기능 동일)
    private func cancelMatchViaFunction() {
        guard let user = Auth.auth().currentUser else { return }
        isCancelling = true
        message = nil

        user.getIDToken { token, err in
            if let err = err {
                self.isCancelling = false
                self.message = "토큰 오류: \(err.localizedDescription)"
                return
            }
            guard let token = token else {
                self.isCancelling = false
                self.message = "토큰 없음"
                return
            }

            var req = URLRequest(url: FunctionsAPI.cancelMatchURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { _, resp, error in
                DispatchQueue.main.async {
                    self.isCancelling = false
                    if let error = error {
                        self.message = "취소 실패: \(error.localizedDescription)"
                        return
                    }
                    if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                        self.message = "매칭을 취소했습니다."
                        self.qhb?.stop()
                        self.qhb = nil
                        self.matchingManager.stop()
                        self.appState.userRequestedMatching = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.dismiss()
                        }
                    } else {
                        self.message = "취소 실패(서버 응답 오류)"
                    }
                }
            }.resume()
        }
    }

    private func tryStartMatchingIfReady() {
        guard appState.userRequestedMatching else { return }
        guard appState.isReadyForQueue, !started else { return }
        started = true
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // 0) dangling room self-heal
        FunctionsAPI.selfHealIfDanglingRoomThen { _ in
            // 1) 서버 기준 프로필 읽기
            let usersRef = Firestore.firestore().collection("users").document(uid)
            usersRef.getDocument(source: .server) { snap, _ in
                let myGender     = (snap?.get("gender") as? String) ?? "남자"
                let myWantGender = (snap?.get("wantGender") as? String) ?? "all"
                let activeRoomId = (snap?.get("activeRoomId") as? String) ?? ""

                // 이미 방이 있으면 큐 등록 생략
                guard activeRoomId.isEmpty else {
                    print("⚠️ 이미 activeRoomId=\(activeRoomId) 있음 → 큐 등록 생략")
                    return
                }

                // 2) 큐 문서 최초 등록
                let ref = Firestore.firestore().collection("matchingQueue").document(uid)
                ref.setData([
                    "uid": uid,
                    "status": "waiting",
                    "gender": myGender,
                    "wantGender": myWantGender,
                    "createdAt": FieldValue.serverTimestamp(),
                    "heartbeatAt": FieldValue.serverTimestamp()
                ], merge: true)

                // 3) 대기 하트비트 시작
                qhb = QueueHeartbeat(uid: uid)
                qhb?.start()

                // 4) 매칭 시도
                matchingManager.startMatching { success in
                    if success {
                        qhb?.stop()
                        qhb = nil
                        matchingManager.stop()
                        isMatched = true
                    } else {
                        print("🟡 아직 매칭 상대 없음. 이후 재시도 가능")
                    }
                }
            }
        }
    }

    // MARK: - Styles (MatchingView 전용 웜보이스 CTA)
    private struct WarmPillButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundColor(.white)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0xFF6B8A), Color(hex: 0xFFB36A)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(configuration.isPressed ? 0.06 : 0.12),
                        radius: configuration.isPressed ? 6 : 12,
                        y: configuration.isPressed ? 3 : 8)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.9),
                           value: configuration.isPressed)
        }
    }


}
