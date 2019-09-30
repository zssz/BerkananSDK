//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import CoreBluetooth

extension BerkananService {
    
  /// The length in bytes for a characteristic write value operation.
  public static let maxCharacteristicWriteValueLength = 512
    
  /// The peripheral service to be added to the local GATT database.
  public static let peripheralService: CBMutableService = {
    let service = CBMutableService(
      type: CBUUID(string: UUIDPeripheralServiceString),
      primary: true
    )
    service.characteristics = [publicBroadcastMessageCharacteristic]
    return service
  }()
  
  /// The characteristic used for receiving public broadcast messages.
  public static let publicBroadcastMessageCharacteristic =
    CBMutableCharacteristic(
      type: CBUUID(string: UUIDPublicBroadcastMessageCharacteristicString),
      properties: [.write],
      value: nil,
      permissions: [.writeable]
  )
}
