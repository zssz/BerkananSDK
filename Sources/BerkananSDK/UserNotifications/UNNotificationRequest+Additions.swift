//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation

#if canImport(UserNotifications)
import UserNotifications

@available(iOS 10.0, OSX 10.14, *)
extension UNNotificationRequest {
  
  public convenience init(
    publicBroadcastMessage message: PublicBroadcastMessage
  ) {
    let notificationContent = UNMutableNotificationContent()
    notificationContent.categoryIdentifier =
      UNNotificationContent.CategoryType.PublicBroadcastMessage.rawValue
    notificationContent.title = message.sourceUser.displayName
    notificationContent.subtitle = NSLocalizedString("Public", comment: "")
    notificationContent.body = message.text ?? ""
    self.init(
      identifier: message.uuid?.uuidString ?? "",
      content: notificationContent,
      trigger: UNTimeIntervalNotificationTrigger(
        timeInterval: 0.01,
        repeats: false
    ))
  }
}
#endif
