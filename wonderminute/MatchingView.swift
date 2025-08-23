import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// ⬇️ 여기 바깥에 QueueHeartbeat 클래스 추가
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
            "heartbeatAt": FieldValue.serverTimestamp(),
            "status": "waiting"
        ], merge: true)
    }
}


struct MatchingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    
    // ⬇️ 추가
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

    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                if !appState.isReadyForQueue {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(2)
                    Text("초기화 중…").foregroundColor(.white)
                } else {
                    ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(2)
                    Text("매칭 중입니다...").font(.title2).foregroundColor(.white)
                }

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    cancelMatchViaFunction()
                } label: {
                    Text(isCancelling ? "취소 중..." : "매칭 취소")
                        .bold()
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white)
                        .foregroundColor(.red)
                        .cornerRadius(12)
                }
                .disabled(isCancelling)
                .padding(.horizontal)

                Spacer()

                NavigationLink(
                    destination: MatchedView(call: call, watcher: watcher),
                    isActive: $isMatched
                ) { EmptyView() }
            }

            if isCancelling {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView()
            }
        }
        .onAppear {
            tryStartMatchingIfReady()
        }
        .onChange(of: isMatched) { matched in
            if matched {
                qhb?.stop()
                qhb = nil
            }
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

    // MARK: - 서버 함수로 취소
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
                        
                        // ✅ 매칭 요청 상태 해제
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

        // 0) 먼저 self-heal 로 과거 방/상태 정리
        FunctionsAPI.selfHealIfDanglingRoomThen { _ in
            // 1) 서버 기준 프로필 읽기
            let usersRef = Firestore.firestore().collection("users").document(uid)
            usersRef.getDocument(source: .server) { snap, _ in
                let myGender     = (snap?.get("gender") as? String) ?? "남자"
                let myWantGender = (snap?.get("wantGender") as? String) ?? "all"

                // 2) 큐 문서 생성/갱신
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
