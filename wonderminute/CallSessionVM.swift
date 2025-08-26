import SwiftUI
import FirebaseFunctions
import FirebaseFirestore
import UIKit
import AudioToolbox

final class CallSessionVM: ObservableObject {
    // 서버 권위
    @Published private(set) var endsAt: Date?
    @Published private(set) var isAutoEndEnabled = false

    // 팝업 재노출 제어: 마지막으로 팝업을 띄운 endsAt(=버전)
    @Published private var lastPromptEndsAt: Date? = nil

    // UI
    @Published var remaining: Int = 0
    @Published var showExtendPrompt = false
    @Published var isEnding = false

    private let roomId: String
    private var uiTicker: DispatchSourceTimer?
    private var autoEndTimer: Timer?
    private var listener: ListenerRegistration?
    private lazy var functions = Functions.functions()

    init(roomId: String) {
        self.roomId = roomId
        print(CallDiag.tag("🟢 CallSessionVM.init roomId=\(roomId)"))
        startSessionListener()
        startUITicker()
    }

    deinit {
        print(CallDiag.tag("🟢 CallSessionVM.deinit"))
        uiTicker?.setEventHandler {}
        uiTicker?.cancel()
        uiTicker = nil

        autoEndTimer?.invalidate(); autoEndTimer = nil
        listener?.remove(); listener = nil
    }

    // MARK: - Firestore 세션 감시
    private func startSessionListener() {
        guard listener == nil else { return }
        let ref = Firestore.firestore().collection("callSessions").document(roomId)
        listener = ref.addSnapshotListener { [weak self] snap, err in
            guard let self = self else { return }
            if let err = err {
                print(CallDiag.tag("🧨 session listen error: \(err)"))
                self.disableAutoEnd("permission/listen error")
                return
            }
            guard let data = snap?.data() else {
                self.disableAutoEnd("no session or permission err")
                return
            }

            if let ts = data["endsAt"] as? Timestamp {
                let newEnds = ts.dateValue()
                self.endsAt = newEnds
                print(CallDiag.tag("⏲️ server endsAt=\(newEnds) pending=\(snap?.metadata.hasPendingWrites ?? false)"))
                self.updateAutoEndGuard()
            } else {
                self.endsAt = nil
                self.disableAutoEnd("no endsAt yet")
            }

            if let status = data["status"] as? String {
                print(CallDiag.tag("📄 session status='\(status)'"))
                if status == "ended" { self.isEnding = true }
            }
        }
    }

    // MARK: - Auto-End
    private func updateAutoEndGuard() {
        guard let ends = endsAt else { disableAutoEnd("no endsAt yet"); return }
        let remain = ends.timeIntervalSinceNow
        if remain <= 0 { return }
        enableAutoEnd(after: remain, forceReset: true)
    }

    private func enableAutoEnd(after seconds: TimeInterval, forceReset: Bool = false) {
        if !forceReset && isAutoEndEnabled { return }
        isAutoEndEnabled = true
        autoEndTimer?.invalidate()
        autoEndTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.isEnding {
                print(CallDiag.tag("🛑 auto end (endsAt reached) -> endSession()"))
                self.isEnding = true
                self.endSession()
            }
        }
    }

    private func disableAutoEnd(_ reason: String) {
        isAutoEndEnabled = false
        autoEndTimer?.invalidate()
        autoEndTimer = nil
        print(CallDiag.tag("[AutoEnd] disabled: \(reason)"))
    }


    // MARK: - UI 틱 (잔여/팝업) – GCD 기반
    private func startUITicker() {
        guard uiTicker == nil else { return }
        print(CallDiag.tag("⏱️ ticker start"))

        // 첫 틱 즉시 반영
        if let ends = self.endsAt {
            self.remaining = max(0, Int(ends.timeIntervalSinceNow))
        } else {
            self.remaining = 0
        }

        let q = DispatchQueue(label: "wm.remaining.ticker", qos: .userInteractive)
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(50)) // 첫 틱 즉시
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            let nextRemaining: Int
            if let ends = self.endsAt {
                nextRemaining = max(0, Int(ends.timeIntervalSinceNow))
            } else {
                nextRemaining = 0
            }

            // 팝업/로깅/remaining 갱신은 메인에서
            DispatchQueue.main.async {
                self.remaining = nextRemaining

                if let ends = self.endsAt {
                    let diff = nextRemaining
                    let isNewDeadline = (self.lastPromptEndsAt == nil) || (self.lastPromptEndsAt! != ends)
                    if diff > 0, diff <= 60, isNewDeadline, !self.showExtendPrompt {
                        self.lastPromptEndsAt = ends
                        self.showExtendPrompt = true
                        self.vibrateStrong()
                        print(CallDiag.tag("🔔 T-60 prompt shown for endsAt=\(ends)"))
                    }

                    if diff % 10 == 0 {
                        print(CallDiag.tag("⏱️ remaining=\(self.remaining) endsAt=\(String(describing: self.endsAt))"))
                    }
                }
            }
        }
        uiTicker = t
        t.resume()
    }


    // MARK: - Actions
    func extend(by seconds: Int) {
        showExtendPrompt = false
        print(CallDiag.tag("➕ extend by \(seconds)s"))
        functions.httpsCallable("extendSession").call(["roomId": roomId, "addSeconds": seconds]) { result, err in
            if let err = err {
                print(CallDiag.tag("❌ extend failed: \(err.localizedDescription)"))
            } else {
                print(CallDiag.tag("✅ extend ok data=\(String(describing: result?.data))"))
                // lastPromptEndsAt는 endsAt가 실제로 바뀌면 자동으로 새 버전으로 동작
            }
        }
    }

    func endSession() {
        print(CallDiag.tag("🏁 endSession() callable"))
        functions.httpsCallable("endSession").call(["roomId": roomId]) { result, err in
            print(CallDiag.tag("🏁 endSession result err=\(String(describing: err)) data=\(String(describing: result?.data))"))
        }
    }

    // MARK: - Haptics
    private func vibrateStrong() {
        DispatchQueue.main.async {
            // 가장 강한 알림형
            let notif = UINotificationFeedbackGenerator()
            notif.prepare()
            notif.notificationOccurred(.error)

            // 보강: 헤비 임팩트 2펄스 (짧은 텀)
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            impact.prepare()
            impact.impactOccurred(intensity: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                impact.impactOccurred(intensity: 1.0)
            }

            // 폴백: 특정 기기/환경에서 햅틱 미지원 시 기본 진동
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}
