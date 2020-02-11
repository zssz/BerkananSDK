//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import CoreBluetooth

extension CBPeripheral {
  
  public static let rssiDidChangeNotification = Notification.Name(
    rawValue: "rssiDidChange"
  )  
}
