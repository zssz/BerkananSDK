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
extension UNUserNotificationCenter {
  
  public func removeDeliveredNotifications(
    forCategoryIdentifier categoryIdentifier: String
  ) {
    self.getDeliveredNotifications(
      completionHandler: { [weak self] (notifications) in
        let notificationsToRemove = notifications.filter {
          $0.request.content.categoryIdentifier == categoryIdentifier
        }
        self?.removeDeliveredNotifications(
          withIdentifiers: notificationsToRemove.map { $0.request.identifier }
        )
    })
  }    
}
#endif
