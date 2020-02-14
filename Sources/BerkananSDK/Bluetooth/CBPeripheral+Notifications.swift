//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

import Foundation
import CoreBluetooth

extension CBPeripheral {
  
  public static let rssiDidChangeNotification = Notification.Name(
    rawValue: "rssiDidChange"
  )  
}
