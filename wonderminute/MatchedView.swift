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
    // ⬇️ 추가: UI 애니메이션 전용 상태
    @State private var appear = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // ✅ 공용 테마 배경
            GradientBackground()
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Spacer(minLength: 24)

                // 헤더 카드 (아이콘/텍스트를 시스템 가독 색으로)
                VStack(spacing: 12) {
                    Image(systemName: "phone.fill.arrow.up.right")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                        .scaleEffect(pulse ? 1.03 : 1.0)

                    Text("매칭 성공!")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundColor(.primary)

                    Text("곧 통화가 시작됩니다.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 8)
                .animation(.easeOut(duration: 0.28), value: appear)

                // 카운트다운 인디케이터 (밝은 배경에서도 보이는 대비)
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 10)
                        .frame(width: 140, height: 140)

                    Text("\(countdown)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.primary)
                        .opacity(0.95)
                }
                .padding(.top, 4)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.3).delay(0.05), value: appear)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }

                // 취소 버튼 (고대비 실색 버튼)
                Button {
                    cancelMatchViaFunction()
                } label: {
                    Text(isCancelling ? "취소 중..." : "매칭 취소")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isCancelling ? Color.red.opacity(0.6) : Color.red)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .disabled(isCancelling)
                .padding(.horizontal, 24)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.28).delay(0.1), value: appear)

                // 안내 배너 2종 (텍스트는 .primary, 테두리는 약한 대비)
                VStack(spacing: 10) {
                    // 백그라운드 주의
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("지금 화면을 벗어나면 연결이 지연되거나 취소될 수 있어요. 잠시만 이 화면을 유지해 주세요.")
                            .font(.footnote)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))

                    // 사용자 보호
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "shield.fill")
                            .foregroundColor(.green)
                        Text("안전한 이용을 위해 통화 중 **개인 연락처 공유, 금전 요구·제안, 외부 링크 유도**는 금지됩니다. 위반 시 계정이 제한될 수 있어요.")
                            .font(.footnote)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .opacity(appear ? 1 : 0)
                .animation(.easeOut(duration: 0.28).delay(0.12), value: appear)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 12)


            // 취소 중 오버레이 (로직 동일)
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

            // ✅ UI 애니메이션 시작 (로직 영향 없음)
            appear = true
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }

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
