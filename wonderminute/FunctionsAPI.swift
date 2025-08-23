import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

enum FunctionsAPI {
    private static let base = URL(string: "https://us-central1-wonderminute-7a4c9.cloudfunctions.net")!

    static var cancelMatchURL: URL   { base.appendingPathComponent("cancelMatch") }
    static var heartbeatURL: URL     { base.appendingPathComponent("heartbeat") }
    static var getAgoraTokenURL: URL { base.appendingPathComponent("getAgoraToken") }
    static var enterRoomURL: URL     { base.appendingPathComponent("enterRoom") }
    
    // ✅ onCall(endSession) 래퍼
        static func endSession(roomId: String, completion: ((Bool) -> Void)? = nil) {
            let callable = Functions.functions().httpsCallable("endSession")
            callable.call([ "roomId": roomId ]) { result, error in
                if let error {
                    print(CallDiag.tag("❌ endSession callable error: \(error.localizedDescription)"))
                    completion?(false)
                    return
                }
                print(CallDiag.tag("✅ endSession callable ok"))
                completion?(true)
            }
        }

    // 공통: 헤더 세팅
    private static func applyCommon(_ req: inout URLRequest, token: String?) {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.setValue(CallDiag.rid, forHTTPHeaderField: "X-Call-Rid")
    }

    static func cancelMatch() { cancelMatch { _ in } }

    static func cancelMatch(completion: ((Bool) -> Void)? = nil) {
        guard let user = Auth.auth().currentUser else { completion?(false); return }
        user.getIDToken { token, err in
            var req = URLRequest(url: cancelMatchURL)
            req.httpMethod = "POST"
            applyCommon(&req, token: token)
            print(CallDiag.tag("↗️ cancelMatch – sending"))
            URLSession.shared.dataTask(with: req) { data, resp, error in
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                print(CallDiag.tag("↙️ cancelMatch – status=\(status) error=\(String(describing: error)) body=\(String(data: data ?? Data(), encoding: .utf8) ?? "nil")"))
                DispatchQueue.main.async { completion?(status == 200) }
            }.resume()
        }
    }

    static func heartbeat() {
        guard let user = Auth.auth().currentUser else { return }
        user.getIDToken { token, _ in
            var req = URLRequest(url: heartbeatURL)
            req.httpMethod = "POST"
            applyCommon(&req, token: token)
            URLSession.shared.dataTask(with: req) { data, resp, error in
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                if status != 200 {
                    print(CallDiag.tag("⚠️ heartbeat – status=\(status) error=\(String(describing: error)) body=\(String(data: data ?? Data(), encoding: .utf8) ?? "nil")"))
                }
            }.resume()
        }
    }

    static func enterRoom(roomId: String) {
        guard let user = Auth.auth().currentUser else {
            print(CallDiag.tag("❌ enterRoom: no user")); return
        }
        user.getIDToken { token, err in
            if let err { print(CallDiag.tag("❌ enterRoom: token error \(err)")); return }
            var req = URLRequest(url: enterRoomURL)
            req.httpMethod = "POST"
            applyCommon(&req, token: token)
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["roomId": roomId])
            print(CallDiag.tag("↗️ enterRoom – roomId=\(roomId)"))
            URLSession.shared.dataTask(with: req) { data, resp, error in
                let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
                print(CallDiag.tag("↙️ enterRoom – status=\(status) error=\(String(describing: error)) body=\(String(data: data ?? Data(), encoding: .utf8) ?? "nil")"))
            }.resume()
        }
    }

    static func selfHealIfDanglingRoomThen(_ next: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else { next(false); return }
        let db = Firestore.firestore()
        print(CallDiag.tag("🩹 selfHeal – uid=\(uid)"))
        db.collection("users").document(uid).getDocument(source: .server) { snap, _ in
            let roomId = (snap?.get("activeRoomId") as? String) ?? ""
            let phase  = (snap?.get("matchPhase") as? String) ?? "idle"
            print(CallDiag.tag("🩹 selfHeal – users/\(uid) roomId='\(roomId)' phase='\(phase)' exists=\(snap?.exists ?? false)"))
            guard !roomId.isEmpty else { next(true); return }

            db.collection("matchedRooms").document(roomId).getDocument(source: .server) { rsnap, _ in
                let exists = (rsnap?.exists == true)
                let users  = (rsnap?.get("users") as? [String]) ?? []
                let status = (rsnap?.get("status") as? String) ?? "pending"
                let iAmIn  = users.contains(uid)
                print(CallDiag.tag("🩹 selfHeal – matchedRooms/\(roomId) exists=\(exists) users=\(users) status='\(status)' iAmIn=\(iAmIn)"))
                let dangling = (!exists || !iAmIn || status == "ended")
                if dangling || phase != "matched" {
                    print(CallDiag.tag("🩹 selfHeal – cleanup via cancelMatch()"))
                    cancelMatch { _ in next(true) }
                } else { next(true) }
            }
        }
    }
}
