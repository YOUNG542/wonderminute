import Foundation
import AgoraRtcKit
import AVFAudio

struct AgoraJoin {
    let appId: String
    let channel: String
    let token: String
    let rtcUid: UInt
    let expireAt: Date
}

final class CallEngine: NSObject, ObservableObject {
    private var engine: AgoraRtcEngineKit?

    // 조인 단일 플라이트
    @Published private(set) var isJoining = false { didSet {
        print(CallDiag.tag("STATE isJoining \(oldValue)→\(isJoining) at \(Date())"))
    }}          // ← (선택) UI가 쓸 거면 퍼블리시
    @Published private(set) var isJoined = false { didSet {
        print(CallDiag.tag("STATE isJoined \(oldValue)→\(isJoined) at \(Date())"))
    }}

    @Published var currentRoomId: String?
    @Published var remoteLeft = false { didSet {
        print(CallDiag.tag("STATE remoteLeft \(oldValue)→\(remoteLeft) at \(Date())"))
    }}
    @Published var remoteEnded = false { didSet {
        print(CallDiag.tag("STATE remoteEnded \(oldValue)→\(remoteEnded) at \(Date())"))
    }}

    @Published var muted = false { didSet {
        print(CallDiag.tag("STATE muted \(oldValue)→\(muted) at \(Date())"))
    }}
    private var lastAppliedMuted = false

    private var reconnectTimer: Timer?
    private let routeObserver = AudioRouteObserver()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleInterruption(_:)),
                                               name: AVAudioSession.interruptionNotification,
                                               object: nil)
        // 라우트 변경은 디바운서 통해 처리
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                               object: AVAudioSession.sharedInstance(),
                                               queue: .main) { [weak self] note in
            self?.routeObserver.handleRouteChange(note) { [weak self] in
                self?.applyMute("route change")
            }
        }
        print(CallDiag.tag("🟣 CallEngine.init"))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        print(CallDiag.tag("🟣 CallEngine.deinit"))
    }

    // MARK: - Join single-flight wrapper
    // MARK: - Join single-flight wrapper
    func joinIfNeeded(_ provider: @escaping () async throws -> AgoraJoin) async {
        guard !isJoined, !isJoining else {
            print(CallDiag.tag("⚠️ join suppressed (isJoined=\(isJoined), isJoining=\(isJoining))"))
            return
        }
        isJoining = true
        defer { isJoining = false }

        do {
            let j = try await provider()
            await actuallyJoin(j)
            isJoined = true
        } catch {
            // 에러 로깅 및 상태 정리
            print(CallDiag.tag("🧨 joinIfNeeded error: \(error)"))
            // 혹시 엔진이 중간에 생성됐다면 정리
            leave()
            isJoined = false
        }
    }


    func leaveIfJoined() {
        guard isJoined else { return }
        leave()
        isJoined = false
    }

    // MARK: - Internals
    private func mask(_ s: String, keep: Int = 6) -> String {
        guard s.count > keep else { return s }
        return String(s.prefix(keep)) + "…(\(s.count))"
    }

    private func configureAudioSession() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try s.setActive(true)
            print(CallDiag.tag("🎧 AudioSession – category=\(s.category.rawValue) mode=\(s.mode.rawValue)"))
        } catch {
            print(CallDiag.tag("❌ AudioSession error: \(error)"))
        }
    }

    private func applyMute(_ reason: String = "unknown") {
        engine?.muteLocalAudioStream(muted)
        lastAppliedMuted = muted
        print(CallDiag.tag("🎚️ applyMute=\(muted) reason=\(reason)"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if self.lastAppliedMuted != self.muted {
                print(CallDiag.tag("⚠️ muted drift detected. lastApplied=\(self.lastAppliedMuted) current=\(self.muted)"))
            } else {
                print(CallDiag.tag("✅ muted stable at \(self.muted)"))
            }
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        let info = note.userInfo ?? [:]
        let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt
        let type = typeVal.flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
        print(CallDiag.tag("🔕 Interruption – info=\(info) parsed=\(String(describing: type))"))
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.applyMute("interruption ended")
            }
        }
    }

    // 실제 조인
    private func actuallyJoin(_ j: AgoraJoin) async {
        if engine != nil { print(CallDiag.tag("⚠️ join() while engine!=nil → leave()")); leave() }
        configureAudioSession()

        print(CallDiag.tag("🚪 join() appId=\(mask(j.appId)) channel=\(j.channel) tokenLen=\(j.token.count) rtcUid=\(j.rtcUid)"))
        let eng = AgoraRtcEngineKit.sharedEngine(withAppId: j.appId, delegate: self)
        engine = eng
        eng.setChannelProfile(.communication)
        eng.enableAudio()
        eng.setDefaultAudioRouteToSpeakerphone(true)

        currentRoomId = j.channel
        let ret = eng.joinChannel(byToken: j.token, channelId: j.channel, info: nil, uid: j.rtcUid) { [weak self] _, _, _ in
            DispatchQueue.main.async { self?.applyMute("join completion") }
        }
        print(CallDiag.tag("🚪 join() returned=\(String(describing: ret))"))
    }

    func leave() {
        print(CallDiag.tag("🏁 leave() called joined=\(isJoined)"))
        engine?.leaveChannel { stats in
            print(CallDiag.tag("🏁 leaveChannel cb duration=\(stats.duration) tx=\(stats.txKBitrate) rx=\(stats.rxKBitrate)"))
        }
        AgoraRtcEngineKit.destroy()
        engine = nil

        print(CallDiag.tag("🧹 reset state (joined=false, muted=false, flags cleared)"))
        isJoined = false
        currentRoomId = nil
        muted = false
        remoteLeft = false
        remoteEnded = false

        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    func toggleMute() {
        muted.toggle()
        print(CallDiag.tag("🖐️ toggleMute -> \(muted)"))
        applyMute("user tap")
    }
}

// MARK: - Agora Delegate
extension CallEngine: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit,
                   didJoinChannel channel: String,
                   withUid uid: UInt,
                   elapsed: Int) {
        print(CallDiag.tag("✅ didJoinChannel ch=\(channel) uid=\(uid) elapsed=\(elapsed)"))
        DispatchQueue.main.async {
            self.reconnectTimer?.invalidate(); self.reconnectTimer = nil
            self.isJoined = true
            self.applyMute("didJoinChannel")
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit,
                   didJoinedOfUid uid: UInt,
                   elapsed: Int) {
        print(CallDiag.tag("👋 remote joined uid=\(uid) elapsed=\(elapsed)"))
        DispatchQueue.main.async {
            self.remoteLeft = false
            self.reconnectTimer?.invalidate(); self.reconnectTimer = nil
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit,
                   didOfflineOfUid uid: UInt,
                   reason: AgoraUserOfflineReason) {
        print(CallDiag.tag("👋 remote offline uid=\(uid) reason=\(reason.rawValue)"))
        DispatchQueue.main.async {
            self.remoteLeft = true
            self.reconnectTimer?.invalidate()
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                guard let self else { return }
                print(CallDiag.tag("⏳ remote reconnection timeout -> end"))
                self.remoteEnded = true
            }
        }
    }

    func rtcEngineConnectionDidInterrupted(_ engine: AgoraRtcEngineKit) {
        print(CallDiag.tag("⚠️ connection interrupted"))
    }

    func rtcEngineConnectionDidLost(_ engine: AgoraRtcEngineKit) {
        print(CallDiag.tag("❌ connection lost (joined=\(isJoined))"))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isJoined else { print(CallDiag.tag("ℹ️ lost before joined → ignore")); return }
            self.reconnectTimer?.invalidate()
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                print(CallDiag.tag("⏳ lost grace elapsed -> remoteEnded=true"))
                self?.remoteEnded = true
            }
        }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit,
                   connectionChangedTo state: AgoraConnectionState,
                   reason: AgoraConnectionChangedReason) {
        print(CallDiag.tag("🔗 connState=\(state.rawValue) reason=\(reason.rawValue)"))
        DispatchQueue.main.async { self.applyMute("conn change") }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit,
                   didAudioRouteChanged routing: AgoraAudioOutputRouting) {
        print(CallDiag.tag("🔊 route=\(routing.rawValue)"))
        // mute 토글은 UI만이 단일 소스. 여기선 단순 재적용만(디바운서도 있음)
        DispatchQueue.main.async { self.applyMute("audio route changed") }
    }

    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurWarning warningCode: AgoraWarningCode) {
        print(CallDiag.tag("⚠️ warning=\(warningCode.rawValue)"))
    }
    func rtcEngine(_ engine: AgoraRtcEngineKit, didOccurError errorCode: AgoraErrorCode) {
        print(CallDiag.tag("🧨 error=\(errorCode.rawValue)"))
    }
}

// MARK: - Audio route debounce
final class AudioRouteObserver {
    private var lastEventAt = Date.distantPast
    private let debounce: TimeInterval = 0.3

    func handleRouteChange(_ note: Notification, perform: () -> Void) {
        let now = Date()
        guard now.timeIntervalSince(lastEventAt) > debounce else { return }
        lastEventAt = now
        // mute 토글은 절대 여기서 하지 않음. IO 재설정/재적용만.
        perform()
    }
}
