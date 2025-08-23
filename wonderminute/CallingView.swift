import SwiftUI
// ⬆️ 파일 맨 위 import 라인 근처에 추가
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

struct CallingView: View {
    @ObservedObject var call: CallEngine            // ⬅️ StateObject → ObservedObject
    @ObservedObject var watcher: MatchWatcher
    @State private var sessionVM: CallSessionVM?   // ✅ 단 한 번만 선언
    // 종료 후 라우팅 콜백...
    let onEnded: () -> Void

    // ⬇️ 외부(MainTabView 등)에서 주입
    init(call: CallEngine, watcher: MatchWatcher, onEnded: @escaping () -> Void) {
        self._call    = ObservedObject(initialValue: call)
        self._watcher = ObservedObject(initialValue: watcher)
        self.onEnded  = onEnded
    }
    @State private var endTapCount = 0
    @State private var endedOnce = false
    @State private var callHbTimer: Timer?
    @State private var hasJoinedOnce = false
    @State private var resolvedRoomId: String?     // (선택) 폴백 확인용
    @State private var elapsed = 0
    @State private var elapsedTimer: Timer?
    

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.brandPurple, Color.brandIndigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer(minLength: 24)

                Text("통화 중")
                    .font(.title2.bold())
                    .foregroundColor(.white.opacity(0.95))
                
                // ⬇️ 남은 시간 라벨 추가
                    if let vm = sessionVM {
                        Text(timeString(from: vm.remaining))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 6)
                    }
                
                // ✅ 경과 시간 라벨 (elapsed)
                Text(String(format: "%02d:%02d", elapsed/60, elapsed%60))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.top, 2)

                if let peer = watcher.peer {
                    VStack(spacing: 12) {
                        AvatarView(urlString: peer.photoURL, nickname: peer.nickname)
                            .frame(width: 96, height: 96)
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)

                        Text(peer.nickname)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)

                        HStack(spacing: 8) {
                            if let mbti = peer.mbti, !mbti.isEmpty { Chip(mbti) }
                            if let g = peer.gender, !g.isEmpty { Chip(g) }
                        }

                        if let ints = peer.interests, !ints.isEmpty {
                            Text(ints.joined(separator: " • "))
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        
                      
                    }
                    .padding(.horizontal, 20)
                } else {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.2)
                        .padding(.top, 8)
                }
              

                Spacer()

                HStack {
                    Image(systemName: "person.wave.2")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())

                    Text("매너있는 대화를 위해 SNS 요구, 부적절한 언행 시 계정이 정지될 수 있어요.")
                        .font(.footnote)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal)

                // 컨트롤 바: 음소거 / 종료
                HStack(spacing: 16) {
                    Button { call.toggleMute() } label: {
                        VStack(spacing: 6) {
                            Image(systemName: call.muted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text(call.muted ? "음소거 해제" : "음소거")
                                .font(.caption2).fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    }

                    Button {
                        endTapCount += 1
                        print("🛎️ End tapped at \(Date()) | endedOnce=\(endedOnce) hasJoinedOnce=\(hasJoinedOnce) isJoined=\(call.isJoined) remoteEnded=\(call.remoteEnded) roomId=\(call.currentRoomId ?? "nil")")
                            
                        endCallAndNavigate()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 20, weight: .semibold))
                            Text("종료")
                                .font(.caption2).fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
            // ⬇️ 오버레이는 ZStack의 "형제"로
                        if let vm = sessionVM, vm.showExtendPrompt {
                            extendSheet(vm: vm)
                                .zIndex(1)
                                .transition(.scale.combined(with: .opacity)) // (선택)
                                .animation(.spring(), value: vm.showExtendPrompt) // (선택)
                        }
        }
        .onAppear {
            print("🟪 [Call] onAppear at \(Date())")
            CallLifecycle.shared.call = call
            startCallHeartbeat()
            
            watcher.start()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                ensureSessionVM()
               
            }
        }


        .onDisappear {
            print("⬅️ [Call] onDisappear at \(Date()) – cleanup only")
            CallLifecycle.shared.call = nil
            stopCallHeartbeat()
            watcher.stop()
            call.leave()
            // ❌ FunctionsAPI.cancelMatch()는 여기서 호출하지 않음
        }

        .onChange(of: call.isJoined) { joined in
            print("🔗 [Call] isJoined -> \(joined) at \(Date())")
            if joined {
                print(CallDiag.tag("⏱️ elapsed start"))
                hasJoinedOnce = true
                elapsed = 0
                elapsedTimer?.invalidate()
                elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    elapsed += 1
                }
            } else {
                print(CallDiag.tag("⏱️ elapsed stop"))
                elapsedTimer?.invalidate()
                elapsedTimer = nil
            }
        }
        .onChange(of: call.remoteEnded) { ended in
            print("🔔 [Call] remoteEnded -> \(ended) at \(Date()) (hasJoinedOnce=\(hasJoinedOnce))")
            if ended { endCallAndNavigate() }
        }
        .onChange(of: sessionVM?.isEnding ?? false) { ending in
            print("🧷 [Call] sessionVM.isEnding -> \(ending) at \(Date()) (hasJoinedOnce=\(hasJoinedOnce))")
            if ending, hasJoinedOnce { endCallAndNavigate() }
        }

    }

    // MARK: - Helpers
    private func endCallAndNavigate() {
        print("🚪 [Call] endCallAndNavigate() entered (endedOnce=\(endedOnce), joined=\(call.isJoined), remoteEnded=\(call.remoteEnded))")
        guard !endedOnce else { print("⛔ [Call] blocked by endedOnce guard"); return }
        endedOnce = true

        let rid = call.currentRoomId ?? resolvedRoomId

        // 로컬 정리
        stopCallHeartbeat()
        watcher.stop()
        call.leave()
        resolvedRoomId = nil   // ✅ 재진입 방지

        // ✅ 2) 서버 종료는 roomId가 있으면 "무조건" 시도 (멱등)
        if let rid {
            FunctionsAPI.endSession(roomId: rid)
            print("🧮 [Call] endSession(rid=\(rid)) sent (force)")
        } else {
            // join 전 조기취소만 가능한 상황
            FunctionsAPI.cancelMatch()
            print("🕊️ [Call] cancelMatch() sent (no roomId)")
        }

        // 3) 네비게이션
        onEnded()
        NotificationCenter.default.post(name: .init("WonderMinute.NavigateToCall"), object: nil)

        // (권장) 혹시 매칭 자동시작 플래그 쓰면 꺼주기
        // AppState.shared.userRequestedMatching = false
    }




    private func startCallHeartbeat() {
        stopCallHeartbeat()
        FunctionsAPI.heartbeat() // 즉시 1회
        callHbTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { _ in
            FunctionsAPI.heartbeat()
        }
    }

    private func stopCallHeartbeat() {
        callHbTimer?.invalidate()
        callHbTimer = nil
    }

    // MARK: - 작은 UI 컴포넌트들
    private struct AvatarView: View {
        let urlString: String?
        let nickname: String

        var body: some View {
            Group {
                if let urlString, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Placeholder()
                        }
                    }
                } else {
                    Placeholder()
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            .shadow(radius: 2, y: 1)
        }

        @ViewBuilder
        private func Placeholder() -> some View {
            ZStack {
                Color.gray.opacity(0.2)
                Text(initials(from: nickname))
                    .font(.title2.bold())
                    .foregroundColor(.gray)
            }
        }

        private func initials(from name: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
        }
    }

    private struct Chip: View {
        let text: String
        init(_ text: String) { self.text = text }
        var body: some View {
            Text(text)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.18))
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
    }
    // ⬇️ 파일 맨 아래 Helpers 근처에 추가

    private func extendSheet(vm: CallSessionVM) -> some View {
        VStack(spacing: 14) {
            Text("통화 시간이 1분 밖에 남지 않았습니다!\n연장하시겠어요??")
                .multilineTextAlignment(.center)
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 12) {
                Button("7분 연장") { vm.extend(by: 420) }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Button("10분 연장") { vm.extend(by: 600) }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button("이번엔 종료할게요") { vm.showExtendPrompt = false }
                .foregroundColor(.white.opacity(0.85))
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(24)
    }

    private func timeString(from seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func ensureSessionVM() {
        // 이미 생성되어 있으면 패스
        if sessionVM != nil { return }

        // 1순위: CallEngine에서 roomId 확보
        if let rid = call.currentRoomId {
            resolvedRoomId = rid
            sessionVM = CallSessionVM(roomId: rid)
            
            return
        }

        // 2순위: Firestore users/{uid}.activeRoomId 폴백
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid)
            .getDocument(source: .server) { snap, _ in
                if let rid = snap?.get("activeRoomId") as? String, !rid.isEmpty {
                    resolvedRoomId = rid
                    sessionVM = CallSessionVM(roomId: rid)
                } else {
                    // 서버 기준으로 방이 없으면 폴백 생성 금지
                    resolvedRoomId = nil
                }
            }

    }

    
}
