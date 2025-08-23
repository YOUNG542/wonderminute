import Foundation

enum CallDiag {
    // 현재 통화 세션의 상관 ID (앱 재시작 전까지 유지)
    static var rid: String = {
        let base = UUID().uuidString.split(separator: "-").first ?? "RID"
        return String(base)
    }()

    static func newRID() {
        rid = UUID().uuidString.split(separator: "-").first.map(String.init) ?? String(Int.random(in: 1000...9999))
        print("🧭[RID] new session rid=\(rid)")
    }

    static func tag(_ msg: String) -> String { "[rid:\(rid)] " + msg }
}
