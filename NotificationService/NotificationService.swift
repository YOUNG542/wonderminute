import UserNotifications
import UIKit
import Intents

final class NotificationService: UNNotificationServiceExtension {

  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?

  // ✅ 라벨명 수정: withContentHandler
  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
    self.bestAttemptContent = content

    // ===== 1) 데이터 파싱 =====
    // userInfo는 [AnyHashable: Any] → 문자열 키 딕셔너리로 변환
    let userInfoAny = content.userInfo
    let userInfo: [String: Any] = Self.toStringKeyDict(userInfoAny)

    // data 블록 우선, 없으면 userInfo 전체 사용
    let data: [String: Any] = {
      if let dAny = userInfoAny["data"] as? [AnyHashable: Any] {
        return Self.toStringKeyDict(dAny)
      }
      if let d = userInfo["data"] as? [String: Any] { // 혹시 이미 String 키면
        return d
      }
      return userInfo
    }()

    let senderName = (data["senderName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? (content.title.isEmpty ? "새 메시지" : content.title)

    let message = (data["message"] as? String) ?? content.body
    let threadId = (data["threadId"] as? String) ?? (data["roomId"] as? String)
    let fromUid = (data["fromUid"] as? String) ?? "unknown"   // ✅ 추가


    // 프로필 이미지 URL (https 권장)
    let senderPhotoURL: String? = (data["senderPhotoURL"] as? String)
      ?? (userInfo["image"] as? String)

    // 제목/본문/스레드 보정
    content.title = senderName
    content.body = message
    if let t = threadId, !t.isEmpty { content.threadIdentifier = t }

      // ===== 2) 커뮤니케이션 메타 (attachments 사용 안 함) =====
      let finishWith: (URL?) -> Void = { [weak self] localFile in
        guard let self else { return contentHandler(content) }
        var best = self.bestAttemptContent ?? content

        // ✅ 커뮤니케이션 알림 Intent 주입 → 왼쪽 원형 아바타 렌더
        let handle  = INPersonHandle(value: fromUid, type: .unknown)
        let inImage = localFile.flatMap { INImage(url: $0) } // 이미지 없으면 nil
        let person  = INPerson(
          personHandle: handle,
          nameComponents: nil,
          displayName: senderName,
          image: inImage,
          contactIdentifier: nil,
          customIdentifier: fromUid,
          isMe: false,
          suggestionType: .instantMessageAddress
        )

          // iOS15+ 생성자(throwing)만 사용. 15 미만은 Intent 주입 생략.
          let intent: INSendMessageIntent?
          if #available(iOS 15.0, *) {
            intent = try? INSendMessageIntent(
              recipients: nil, // sender만 설정
              outgoingMessageType: INOutgoingMessageType(rawValue: 0)!, // 0 == outgoing
              content: message,
              speakableGroupName: nil,
              conversationIdentifier: threadId,
              serviceName: nil,
              sender: person,
              attachments: nil
            )
          } else {
            intent = nil
          }

          if let intent,
             let comm = (try? best.updating(from: intent)) as? UNMutableNotificationContent {
            best = comm // 커뮤니케이션 알림 스타일 적용
          }


        self.contentHandler?(best)
      }

      // 이미지가 없어도 커뮤니케이션 메타만 적용
      if
        let urlStr = senderPhotoURL,
        let url = URL(string: urlStr),
        ["https","http"].contains(url.scheme?.lowercased() ?? "")
      {
        downloadImage(url: url) { [weak self] localFile in
          guard let self else { return contentHandler(content) }
          finishWith(localFile)
        }
      } else {
        finishWith(nil)
      }


  }

  override func serviceExtensionTimeWillExpire() {
    if let handler = contentHandler, let content = bestAttemptContent {
      handler(content) // 타임아웃 시 현재까지 결과로 마무리
    }
  }

  // MARK: - Helpers

  // AnyHashable 키 딕셔너리를 String 키 딕셔너리로 변환
  private static func toStringKeyDict(_ dict: [AnyHashable: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (k, v) in dict {
      if let ks = k as? String { out[ks] = v }
    }
    return out
  }

  private func downloadImage(url: URL, completion: @escaping (URL?) -> Void) {
    let task = URLSession.shared.dataTask(with: url) { data, _, _ in
      guard let data, !data.isEmpty else { return completion(nil) }
      let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("jpg")
      do {
        try data.write(to: tmp)
        completion(tmp)
      } catch {
        completion(nil)
      }
    }
    task.resume()
  }
}










