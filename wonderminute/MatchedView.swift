import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import AVFAudio

struct MatchedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @ObservedObject var call: CallEngine
    @ObservedObject var watcher: MatchWatcher
    init(call: CallEngine, watcher: MatchWatcher) {
        self.call = call
        self.watcher = watcher
    }

    @State private var isCancelling = false
    @State private var message: String?
    @State private var hbTimer: Timer?
    @State private var scheduledAt: Date?
    @State private var didCallEnterRoom = false
    @State private var connectWorkItem: DispatchWorkItem?
    @State private var countdown = 3
    @State private var navTask: Task<Void, Never>? = nil
    @State private var didPresent = false
    @State private var csListener: ListenerRegistration? = nil
    @State private var roomIdCache: String = ""
    // ✅ 종료 이후 재시작/재오픈을 막는 가드
    @State private var terminated = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                Text("🎉 매칭 성공!").font(.largeTitle.bold()).foregroundColor(.white)
                Text("곧 통화가 시작됩니다.").font(.title2).foregroundColor(.white.opacity(0.9))
                Text("\(countdown)").font(.system(size: 48, weight: .bold)).foregroundColor(.white).opacity(0.9)

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
                        .bold().frame(maxWidth: .infinity).padding()
                        .background(Color.white).foregroundColor(.red).cornerRadius(12)
                }
                .disabled(isCancelling)
                .padding(.horizontal)

                Spacer()
            }
            .padding()

            if isCancelling {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView()
            }
        }
        .onAppear {
            print("🎯 [Matched] onAppear at \(Date())")
            guard !terminated else {
                print("⛔️ [Matched] terminated=true → 재시작 안 함")
                return
            }
            scheduledAt = Date()
            startCountdownAndPresent()
        }
        .onDisappear {
            print("👋 [Matched] onDisappear at \(Date()) – stop timers & cancel connect")
            terminated = true 
            navTask?.cancel()
            navTask = nil
            csListener?.remove(); csListener = nil
            stopHeartbeat()
        }

    }

    private func startCountdownAndPresent() {
        guard !terminated else { return } // ✅ 재실행 가드
        navTask?.cancel()
        didPresent = false
        countdown = 3
        print("⏳ [Matched] startCountdown 3s")

        navTask = Task { @MainActor in
            while countdown > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                countdown -= 1
                print("🔢 [Matched] countdown=\(countdown)")
            }

            guard !terminated else { return }

            // 3초 끝난 뒤 최신 상태 확인
            guard let rid = await currentRoomId(), !rid.isEmpty else {
                print("🚫 [Matched] no valid room → force cancel & exit")
                await forceCleanupAndExit()
                return
            }
            roomIdCache = rid

            // 마이크 권한
            let granted = await requestMicPermission()
            guard granted else {
                message = "마이크 권한이 필요합니다…"
                return
            }

            // 서버에 enterRoom(읽기→쓰기 트랜잭션) 호출 — 단 한 번만 보장
            guard !didCallEnterRoom else {
                print("⚠️ [Matched] enterRoom already called → skip duplicate")
                await observeCallSessionOnce(roomId: rid)   // 상태 관찰만 이어감
                return
            }
            didCallEnterRoom = true
            do {
                try await enterRoom(roomId: rid)
            } catch {
                print("❌ [Matched] enterRoom failed: \(error)")
                message = "방 입장에 실패했어요. 다시 시도해주세요."
                await forceCleanupAndExit()
                return
            }

            // callSessions/{roomId}.status 가 "active"/"live" 되면 화면 전환
            await observeCallSessionOnce(roomId: rid)
        }
    }

    @MainActor
    private func checkRoomReady() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .getDocument(source: .server)
            let phase = (snap.get("matchPhase") as? String) ?? "idle"
            let room  = (snap.get("activeRoomId") as? String) ?? ""
            print("📖 [Matched] phase=\(phase) room=\(room.isEmpty ? "nil" : room)")
            return phase == "matched" && !room.isEmpty
        } catch {
            print("❌ [Matched] checkRoomReady error: \(error)")
            return false
        }
    }

    @MainActor
    private func currentRoomId() async -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .getDocument(source: .server)
            return (snap.get("activeRoomId") as? String) ?? ""
        } catch {
            print("❌ [Matched] currentRoomId error: \(error)")
            return nil
        }
    }

    private func requestMicPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { cont.resume(returning: granted) }
            }
        }
    }

    // MARK: - enterRoom(HTTPS)
    @MainActor
    private func enterRoom(roomId: String) async throws {
        guard let user = Auth.auth().currentUser else { throw NSError(domain: "auth", code: 0) }
        let token = try await user.getIDTokenResult().token
        var req = URLRequest(url: FunctionsAPI.enterRoomURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["roomId": roomId])
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "enterRoom", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // MARK: - callSessions/{roomId} 상태 감지 (active 또는 live)
    @MainActor
    private func observeCallSessionOnce(roomId: String) async {
        guard !terminated else { return }
        csListener?.remove(); csListener = nil
        let ref = Firestore.firestore().collection("callSessions").document(roomId)
        var completed = false

        csListener = ref.addSnapshotListener { snap, _ in
            Task { @MainActor in
                guard !terminated else { return }
                let status = (snap?.get("status") as? String) ?? ""
                print("👂 callSessions/\(roomId) status=\(status)")
                 if (status == "active" || status == "live"), !completed, !didPresent {
                     completed = true
                     didPresent = true
                     // ✅ MainTabView가 표시할 수 있도록 roomId를 신호로 넘김
                     appState.userRequestedMatching = false
                     call.currentRoomId = roomId
                     // ✅ 나는 퇴장 (프레젠터 1곳만 남기기)
                     dismiss()
                     csListener?.remove(); csListener = nil
                 }
            }
        }

        // 5초 안에 active/live 못 오면, 마지막 안전망
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !terminated else { return }
            if !completed && !didPresent {
                if await hasValidRoomId() {
                    print("⏱️ fallback: user.activeRoomId 존재 → 진입")
                     didPresent = true
                     call.currentRoomId = roomId
                     dismiss()
                } else {
                    print("⏱️ fallback: room still invalid → cleanup")
                    await forceCleanupAndExit()
                }
                csListener?.remove(); csListener = nil
            }
        }
    }

    private func cancelMatchViaFunction() {
        guard let user = Auth.auth().currentUser else {
            print("❌[MatchedView] cancelMatch: no user")
            return
        }
        isCancelling = true
        message = nil
        connectWorkItem?.cancel()
      
        print("🔎[MatchedView] cancelMatchViaFunction – canceled connectWorkItem & hide call")

        user.getIDToken { token, err in
            if let err = err {
                self.isCancelling = false
                self.message = "토큰 오류: \(err.localizedDescription)"
                print("❌[MatchedView] getIDToken error: \(err)")
                return
            }
            guard let token = token else {
                self.isCancelling = false
                self.message = "토큰 없음"
                print("❌[MatchedView] getIDToken: token nil")
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
                        print("❌[MatchedView] cancelMatch fetch error: \(error)")
                        return
                    }
                    if let http = resp as? HTTPURLResponse {
                        print("🔎[MatchedView] cancelMatch status=\(http.statusCode)")
                        if http.statusCode == 200 {
                            self.message = "매칭이 취소되었습니다."
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.dismiss() }
                        } else {
                            self.message = "취소 실패(서버 응답 오류)"
                        }
                    } else {
                        print("❌[MatchedView] cancelMatch: no HTTPURLResponse")
                    }
                }
            }.resume()
        }
    }

    private func startHeartbeat() {
        stopHeartbeat()
        print("🔎[MatchedView] startHeartbeat (every 10s, + immediate)")
        hbTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            self.sendHeartbeat()
        }
        sendHeartbeat()
    }

    private func stopHeartbeat() {
        hbTimer?.invalidate()
        hbTimer = nil
        print("🔎[MatchedView] stopHeartbeat")
    }

    private func sendHeartbeat() {
        guard let user = Auth.auth().currentUser else { return }
        user.getIDToken { token, _ in
            guard let token = token else { return }
            var req = URLRequest(url: FunctionsAPI.heartbeatURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            URLSession.shared.dataTask(with: req) { _, resp, error in
                if let error = error {
                    print("❌[MatchedView] heartbeat error: \(error.localizedDescription)")
                } else if let http = resp as? HTTPURLResponse {
                    print("🔎[MatchedView] heartbeat status=\(http.statusCode)")
                } else {
                    print("❌[MatchedView] heartbeat: no HTTPURLResponse")
                }
            }.resume()
        }
    }

    @MainActor
    private func forceCleanupAndExit() async {
        cancelMatchViaFunction()
        try? await Task.sleep(nanoseconds: 400_000_000)
        dismiss()
    }
}

@MainActor
private func hasValidRoomId() async -> Bool {
    guard let uid = Auth.auth().currentUser?.uid else { return false }
    do {
        let snap = try await Firestore.firestore()
            .collection("users").document(uid)
            .getDocument(source: .server)
        let room = (snap.get("activeRoomId") as? String) ?? ""
        return !room.isEmpty
    } catch {
        return false
    }
}
