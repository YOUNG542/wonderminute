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

    var body: some View {
        ZStack {
            // ✅ WelcomeView와 동일 톤의 배경
            GradientBackground()   // ✅ 프로젝트 공통 배경 컴포넌트 사용


            VStack(spacing: 20) {
                Spacer(minLength: 24)

                // 헤더 카드
                VStack(spacing: 14) {
                    // 앱 로고가 있으면 교체 가능: Image("AppLogo")
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .padding(16)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                        .scaleEffect(pulse ? 1.03 : 1.0)

                    Text("매칭을 찾는 중이에요")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)

                    Text(appState.isReadyForQueue ? "잠시만 기다려 주세요. 가장 잘 맞는 상대를 찾고 있어요." : "초기화 중…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 6)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 8)
                .animation(.easeOut(duration: 0.28), value: appear)

                // 진행 인디케이터
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 10)
                        .frame(width: 120, height: 120)

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2.0)
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

                // 취소 버튼 (기능 동일)
                Button {
                    cancelMatchViaFunction()
                } label: {
                    Text(isCancelling ? "취소 중..." : "매칭 취소")
                        .bold()
                }
                .buttonStyle(WMDestructiveWhiteButtonStyle())   // ✅ 새 스타일 적용
                .disabled(isCancelling)
                .padding(.horizontal, 24)

                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.28).delay(0.1), value: appear)

                // 안내 배너들
                VStack(spacing: 10) {
                    // 백그라운드 주의
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("매칭 중 앱을 백그라운드로 보내면 매칭이 지연되거나 취소될 수 있어요. 화면을 켜둔 상태로 잠시만 기다려 주세요.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))

                    // 사용자 보호 안내
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.green)
                        Text("안전한 이용을 위해 통화 중 **개인 연락처 공유, 금전 요구·제안, 외부 링크 유도**는 금지됩니다. 위반 시 계정이 제한될 수 있어요.")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
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


}
