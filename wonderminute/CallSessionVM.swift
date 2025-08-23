import SwiftUI
import FirebaseFunctions
import FirebaseFirestore

final class CallSessionVM: ObservableObject {
    // 서버 권위
    @Published private(set) var endsAt: Date?              // ← nil인 동안은 auto-end 금지
    @Published private(set) var isAutoEndEnabled = false

    // UI 표시용
    @Published var remaining: Int = 0                      // 초
    @Published var showExtendPrompt = false
    @Published var hasShownOneMinutePrompt = false
    @Published var isEnding = false

    private let roomId: String
    private var uiTicker: Timer?
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
        uiTicker?.invalidate(); uiTicker = nil
        autoEndTimer?.invalidate(); autoEndTimer = nil
        listener?.remove(); listener = nil
    }

    // MARK: - Firestore 세션 감시 (1회만)
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
                self.endsAt = ts.dateValue()
                print(CallDiag.tag("⏲️ server endsAt=\(self.endsAt!) pending=\(snap?.metadata.hasPendingWrites ?? false)"))
                self.updateAutoEndGuard()
            } else {
                // endsAt가 아직 없음 → 로컬 타이머 금지
                self.endsAt = nil
                self.disableAutoEnd("no endsAt yet")
            }

            if let status = data["status"] as? String {
                print(CallDiag.tag("📄 session status='\(status)'"))
                if status == "ended" { self.isEnding = true }
            }
        }
    }

    // MARK: - Auto-End 가드 (endsAt 도착 후에만)
    private func updateAutoEndGuard() {
        guard let ends = endsAt else { disableAutoEnd("no endsAt yet"); return }
        let remain = ends.timeIntervalSinceNow
        if remain <= 0 {
            // 이미 0이하 → 서버/상대 endSession 로그만 신뢰, 로컬에서 다시 호출하지 않음
            return
        }
        enableAutoEnd(after: remain)
    }

    private func enableAutoEnd(after seconds: TimeInterval) {
        guard !isAutoEndEnabled else { return }
        isAutoEndEnabled = true
        autoEndTimer?.invalidate()
        autoEndTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            // 로컬 종료 트리거는 1회만
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

    // MARK: - UI 틱 (잔여시간/프롬프트만 갱신)
    private func startUITicker() {
        guard uiTicker == nil else { return }
        print(CallDiag.tag("⏱️ ticker start"))
        uiTicker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let diff = Int((self.endsAt ?? Date()).timeIntervalSince(Date()))
            self.remaining = max(0, diff)

            if diff > 0, diff <= 60, !self.hasShownOneMinutePrompt {
                self.hasShownOneMinutePrompt = true
                self.showExtendPrompt = true
                print(CallDiag.tag("🔔 T-60 prompt shown"))
            }

            if diff % 10 == 0 {
                print(CallDiag.tag("⏱️ remaining=\(self.remaining) endsAt=\(String(describing: self.endsAt))"))
            }
        }
    }

    // MARK: - Functions
    func extend(by seconds: Int) {
        showExtendPrompt = false
        print(CallDiag.tag("➕ extend by \(seconds)s"))
        functions.httpsCallable("extendSession").call(["roomId": roomId, "addSeconds": seconds]) { result, err in
            print(CallDiag.tag("➕ extend result err=\(String(describing: err)) data=\(String(describing: result?.data))"))
        }
    }

    func endSession() {
        print(CallDiag.tag("🏁 endSession() callable"))
        functions.httpsCallable("endSession").call(["roomId": roomId]) { result, err in
            print(CallDiag.tag("🏁 endSession result err=\(String(describing: err)) data=\(String(describing: result?.data))"))
        }
    }
}
