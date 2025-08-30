import SwiftUI
// ⬆️ 파일 맨 위 import 라인 근처에 추가
import FirebaseFunctions
import FirebaseFirestore
import FirebaseAuth

// MARK: - Monotonic elapsed ticker (메인런루프 비의존)
final class ElapsedTicker {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "wm.elapsed.ticker", qos: .userInteractive)
    private var startUptime: TimeInterval = 0
    var onTick: ((Int) -> Void)?

    func start() {
        stop()
        startUptime = ProcessInfo.processInfo.systemUptime
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(250), leeway: .milliseconds(30)) // 첫 틱 즉시
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            let sec = max(0, Int(ProcessInfo.processInfo.systemUptime - self.startUptime))
            DispatchQueue.main.async { self.onTick?(sec) }      // UI는 메인에만
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.setEventHandler {} // 사이클 끊기
        timer?.cancel()
        timer = nil
    }

    deinit { stop() }
}


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
    @State private var elapsedTicker = ElapsedTicker()
    @State private var showAvatarPreview = false
    @State private var previewImageURL: URL? = nil
    @State private var previewFallbackInitial = "?"
    @State private var showReportSheet = false
    @State private var showBlockSheet  = false
    
    var body: some View {
        ZStack {
            GradientBackground()   // ✅ 프로젝트 공통 배경

            // ✅ 내용부 전체 스크롤 (상단 상태 카드 ~ 안내 배너)
            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 24)

                    // ✅ 상단 상태 카드
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("통화 중")
                        }
                        .foregroundColor(.white.opacity(0.95))

                        if let vm = sessionVM {
                            Text(timeString(from: vm.remaining))
                                .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                                .foregroundColor(.white)
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.2)
                                .padding(.top, 2)
                        }

                        Text(String(format: "경과 %02d:%02d", elapsed/60, elapsed%60))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.16))
                            .clipShape(Capsule())
                            .padding(.top, 2)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
                    .padding(.horizontal)

                    // ✅ 프로필 카드
                    if let peer = watcher.peer {
                        VStack(spacing: 12) {
                            AvatarView(urlString: peer.photoURL, nickname: peer.nickname)
                                .frame(width: 96, height: 96)
                                .overlay(
                                    Circle().strokeBorder(
                                        LinearGradient(colors: [Color.white.opacity(0.6), .clear],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 2
                                    )
                                )
                                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                                .contentShape(Circle())
                                .onTapGesture {
                                    previewImageURL = resolvePreviewURL(peer.photoURL)   // ✅ 동일한 정리 로직 재사용
                                    let trimmed = peer.nickname.trimmingCharacters(in: .whitespaces)
                                    previewFallbackInitial = trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
                                    showAvatarPreview = true
                                }


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

                    // ✅ 안내 배너 1
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "person.wave.2")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.16))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text("안전한 통화 이용 안내")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.white)

                            Text("• **연락처 요구·외부 링크 유도·부적절한 언행**은 제한될 수 있어요.\n• 앱을 **백그라운드로 전환**하면 통화가 끊길 수 있으니 화면을 켜둔 상태로 이용해 주세요.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal)

                    // ✅ 안내 배너 2
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "timer")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.16))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text("타이머 표시 안내")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.white)

                            Text("일부 기기/상황에서 타이머 숫자가 간헐적으로 늦게 갱신될 수 있어요. 하지만 실제 통화 시간 계산과 자동 종료는 서버 시계와 내부 모노토닉 타이머로 정확히 동작하므로 이용에는 지장이 없습니다.")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .padding(.horizontal)

                    // ⬇️ 하단 컨트롤바와 겹치지 않게 여백
                    Spacer(minLength: 80)
                }
            }

            // ✅ 연장 시트는 ZStack 안에서만 조건 표시
            if let vm = sessionVM, vm.showExtendPrompt {
                extendSheet(vm: vm)
                    .zIndex(1)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.spring(), value: vm.showExtendPrompt)
            }
        }
        // ⬇️ 상단 오버레이 고정
        .overlay(
            TopBarOverlay(
                onReport: { showReportSheet = true },
                onBlock:  { showBlockSheet  = true }
            )
            .padding(.horizontal, 14)
            .padding(.top, 10),
            alignment: .top
        )

        // ⬇️ 하단 컨트롤바 고정
        .safeAreaInset(edge: .bottom) {
            ControlBar(
                muted: call.muted,
                onToggleMute: { call.toggleMute() },
                onEnd: {
                    endTapCount += 1
                    print("🛎️ End tapped ...")
                    endCallAndNavigate()
                }
            )
        }
        // ⬇️ 나머지 라이프사이클/상태 변경 핸들러 유지
        .onAppear {
            print("🟪 [Call] onAppear at \(Date())")
            CallLifecycle.shared.call = call
            startCallHeartbeat()
            watcher.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ensureSessionVM() }
        }
        .fullScreenCover(isPresented: $showAvatarPreview) {
            AvatarPreviewView(imageURL: previewImageURL, fallbackInitial: previewFallbackInitial) {
                showAvatarPreview = false
            }
        }
        // ⬇️ ZStack 바깥 modifier들 끝나기 전에 시트 두 개 추가
        .sheet(isPresented: $showReportSheet) {
            if let peer = watcher.peer {
                ReportSheetView(
                    peerUid: peer.id,
                    peerNickname: peer.nickname,
                    roomId: resolvedRoomId ?? call.currentRoomId,
                    callElapsedSec: elapsed
                ) {
                    print("✅ 신고 제출 완료")
                }
            }
        }

        .sheet(isPresented: $showBlockSheet) {
            if let peer = watcher.peer {
                BlockSheetView(
                    peerUid: peer.id,
                    peerNickname: peer.nickname
                ) { endNow in
                    // 차단 완료 → 즉시 종료 선택 시 끝내기
                    if endNow { endCallAndNavigate() }
                }
            }
        }

        .onDisappear {
            print("⬅️ [Call] onDisappear at \(Date()) – cleanup only")
            CallLifecycle.shared.call = nil
            stopCallHeartbeat()
            watcher.stop()
            call.leave()
            elapsedTicker.stop()
            sessionVM = nil
        }
        .onChange(of: call.isJoined) { joined in
            print("🔗 [Call] isJoined -> \(joined) at \(Date())")
            if joined {
                print(CallDiag.tag("⏱️ elapsed start"))
                hasJoinedOnce = true
                elapsed = 0
                elapsedTicker.onTick = { sec in elapsed = sec }
                elapsedTicker.start()
            } else {
                print(CallDiag.tag("⏱️ elapsed stop"))
                elapsedTicker.stop()
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
        FunctionsAPI.heartbeat()
        let t = Timer(timeInterval: 7, repeats: true) { _ in
            FunctionsAPI.heartbeat()
        }
        callHbTimer = t
        RunLoop.main.add(t, forMode: .common)   // ✅ 변경
    }

    private func stopCallHeartbeat() {
        callHbTimer?.invalidate()
        callHbTimer = nil
    }

    // MARK: - 작은 UI 컴포넌트들
    private struct AvatarView: View {
        let urlString: String?
        let nickname: String

        // body 바깥 계산 프로퍼티
        private var resolvedURL: URL? {
            resolveURL(from: urlString)
        }

        var body: some View {
            Group {
                if let resolved = resolvedURL {
                    AsyncImage(url: resolved) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .onAppear {
                                    print("🖼️ Avatar success | url=\(resolved.absoluteString)")
                                }

                        case .failure(let error):
                            Placeholder()
                                .onAppear {
                                    print("🖼️ Avatar FAILURE | url=\(resolved.absoluteString) | error=\(String(describing: error))")
                                    Task {
                                        await probeHTTP(resolved)
                                    }
                                }

                        case .empty:
                            ProgressView()
                                .onAppear {
                                    print("🖼️ Avatar loading... | url=\(resolved.absoluteString)")
                                }

                        }
                    }
                    .onAppear {
                        print("🔎 Avatar onAppear | nickname=\(nickname)")
                    }
                } else {
                    // URL 해석 실패(로그는 resolveURL 내부에서 이미 출력)
                    Placeholder()
                }
            }
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
            .shadow(radius: 2, y: 1)
        }

        // MARK: - 진단: URL 해석 & 사전 검증
        private func resolveURL(from raw: String?) -> URL? {
            guard let raw else {
                print("❗ Avatar URL nil (no photoURL) | nickname=\(nickname)")
                return nil
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                print("❗ Avatar URL empty string | nickname=\(nickname)")
                return nil
            }

            if trimmed.hasPrefix("gs://") {
                print("⚠️ Avatar URL uses gs:// (Firebase Storage) — not directly downloadable. Use downloadURL(). | url=\(trimmed)")
            }

            let sanitized = sanitizeURLString(trimmed)
            guard let url = URL(string: sanitized) else {
                print("❗ Avatar URL init failed | raw=\(trimmed) | sanitized=\(sanitized)")
                return nil
            }

            if url.scheme?.lowercased() == "http" {
                print("⚠️ Avatar URL is http (ATS may block). Consider https or NSAppTransportSecurity exceptions. | url=\(url)")
            }

            print("✅ Avatar resolved URL | raw=\(trimmed) | sanitized=\(sanitized)")
            return url
        }

        // 퍼센트 인코딩 보정
        private func sanitizeURLString(_ s: String) -> String {
            if URL(string: s) != nil { return s }
            if let comps = URLComponents(string: s), let rebuilt = comps.url?.absoluteString {
                return rebuilt
            }
            let allowed = CharacterSet.urlFragmentAllowed
                .union(.urlHostAllowed)
                .union(.urlPathAllowed)
                .union(.urlQueryAllowed)
                .union(.urlUserAllowed)
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        }

        // MARK: - 실패 시 HTTP 상태/리다이렉트 진단
        private func probeHTTP(_ url: URL) async {
            do {
                var req = URLRequest(url: url, timeoutInterval: 10)
                req.httpMethod = "HEAD"
                let (_, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse {
                    print("🛰️ Avatar HEAD | status=\(http.statusCode) | url=\(url)")
                    if let finalURL = http.url, finalURL != url {
                        print("↪️ Avatar redirected to | \(finalURL.absoluteString)")
                    }
                } else {
                    print("🛰️ Avatar HEAD | non-HTTP response | url=\(url)")
                }
            } catch {
                print("💥 Avatar HEAD error | \(error) | url=\(url)")
            }
        }

        // MARK: - UI
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
        VStack(spacing: 16) {
            Text("통화 종료까지 1분 남았어요.\n연장하시겠어요?")
                .multilineTextAlignment(.center)
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            HStack(spacing: 12) {
                Button(action: { vm.extend(by: 420) }) {
                    Text("7분 연장")
                        .font(.callout.bold())
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))

                Button(action: { vm.extend(by: 600) }) {
                    Text("10분 연장")
                        .font(.callout.bold())
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.18), lineWidth: 1))
            }

            Button("이번엔 종료할게요") {
                vm.showExtendPrompt = false
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(.top, 2)
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12), lineWidth: 1))
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
    
    // MARK: - Top overlay (좌: 미닛 / 우: 신고·차단)
    private struct TopBarOverlay: View {
        let onReport: () -> Void
        let onBlock:  () -> Void

        var body: some View {
            HStack {
                MinuteBadgeCompact(count: 0)
                Spacer()

                HStack(spacing: 10) {
                    Button(action: { onReport() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 13, weight: .bold))
                            Text("신고").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                        .shadow(color: .black.opacity(0.20), radius: 10, y: 6)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onBlock() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.raised.fill").font(.system(size: 13, weight: .bold))
                            Text("차단").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                        .shadow(color: .black.opacity(0.20), radius: 10, y: 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 남아있는 미닛 배지(우측 상단 배지와 톤 통일)
    private struct MinuteBadgeCompact: View {
        let count: Int
        var body: some View {
            HStack(spacing: 6) {
                Image("WMPhoneDot")
                    .renderingMode(.template)
                    .resizable().scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.white)
                Text("\(count)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("남아있는 미닛 \(count)")
        }
    }

// MARK: - 하단 고정 컨트롤바
private struct ControlBar: View {
    let muted: Bool
    let onToggleMute: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onToggleMute) {
                VStack(spacing: 6) {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text(muted ? "음소거 해제" : "음소거")
                        .font(.caption2).fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            }

            Button(action: onEnd) {
                VStack(spacing: 6) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("종료")
                        .font(.caption2).fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background( // 뒷배경 살짝 블러/그라데이션 느낌 유지
            Color.black.opacity(0.001) // 터치영역 유지용
                .background(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

    
    // MARK: - Avatar Fullscreen Preview (핀치줌/더블탭/닫기)
    private struct AvatarPreviewView: View {
        let imageURL: URL?
        let fallbackInitial: String
        let onClose: () -> Void

        @Environment(\.dismiss) private var dismiss
        @State private var scale: CGFloat = 1.0
        @State private var lastScale: CGFloat = 1.0
        @State private var offset: CGSize = .zero
        @State private var lastOffset: CGSize = .zero

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                Group {
                    if let url = imageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFit()

                            case .empty:   // ⬅️ 로딩 중
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)

                            case .failure:
                                placeholder

                            @unknown default:
                                placeholder
                            }
                        }

                    } else {
                        placeholder
                    }
                }
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            // 자연스러운 확대 범위(1x ~ 5x)
                            scale = min(max(1.0, lastScale * value), 5.0)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { g in
                            // 확대 상태에서만 패닝 허용
                            guard scale > 1.0 else { return }
                            offset = CGSize(width: lastOffset.width + g.translation.width,
                                            height: lastOffset.height + g.translation.height)
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
                .onTapGesture(count: 2) {
                    // 더블탭 줌 토글
                    if scale > 1.0 {
                        withAnimation(.spring()) {
                            scale = 1.0
                            lastScale = 1.0
                            offset = .zero
                            lastOffset = .zero
                        }
                    } else {
                        withAnimation(.spring()) {
                            scale = 2.0
                            lastScale = 2.0
                        }
                    }
                }

                // 상단 닫기 버튼
                VStack {
                    HStack {
                        Button {
                            if let _ = try? dismiss() {
                                // no-op
                            }
                            onClose()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white.opacity(0.95))
                                .shadow(radius: 6, y: 2)
                        }
                        .padding(.leading, 20)
                        .padding(.top, 14)

                        Spacer()
                    }
                    Spacer()
                }
            }
        }

        @ViewBuilder
        private var placeholder: some View {
            ZStack {
                Color.gray.opacity(0.15)
                Text(fallbackInitial)
                    .font(.system(size: 120, weight: .bold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    // 프리뷰용 URL 정리(퍼센트 인코딩/URLComponents 재조립 포함)
    private func resolvePreviewURL(_ raw: String?) -> URL? {
        guard let raw else {
            print("❗Preview URL nil")
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1차: 그대로 시도
        if let u = URL(string: trimmed) {
            print("✅ Preview URL direct | \(trimmed)")
            return u
        }
        // 2차: URLComponents 재조립
        if let comps = URLComponents(string: trimmed), let u = comps.url {
            print("✅ Preview URL via URLComponents | \(u.absoluteString)")
            return u
        }
        // 3차: 퍼센트 인코딩
        let allowed = CharacterSet.urlFragmentAllowed
            .union(.urlHostAllowed)
            .union(.urlPathAllowed)
            .union(.urlQueryAllowed)
            .union(.urlUserAllowed)
        if let enc = trimmed.addingPercentEncoding(withAllowedCharacters: allowed),
           let u = URL(string: enc) {
            print("✅ Preview URL percent-encoded | raw=\(trimmed) | enc=\(enc)")
            return u
        }

        print("❗Preview URL build failed | raw=\(trimmed)")
        return nil
    }



    
}
