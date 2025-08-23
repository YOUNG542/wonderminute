// CallLifecycle.swift
import UIKit

final class CallLifecycle {
    static let shared = CallLifecycle()
    weak var call: CallEngine?
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    func willEnterBackground() {
        print(CallDiag.tag("🌙 willEnterBackground"))
        guard bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "EndCallIfNeeded") { [weak self] in
            self?.endBgTask()
        }

        call?.leave()
        FunctionsAPI.cancelMatch()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.endBgTask()
        }
    }

    private func endBgTask() {
        if bgTask != .invalid {
            print(CallDiag.tag("🌙 end background task"))
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}
