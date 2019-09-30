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
extension UNNotificationContent {
  
  public enum CategoryType: String {
    case PublicBroadcastMessage
  }
}
#endif
