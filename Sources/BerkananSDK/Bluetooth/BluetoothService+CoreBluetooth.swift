//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import CoreBluetooth

extension BluetoothService {
  
  /// The length in bytes for a characteristic's value.
  public static let maxCharacteristicValueLength = 512
  
  /// The peripheral service to be added to the local GATT database.
  public static var peripheralService: CBMutableService {
    let service = CBMutableService(
      type: CBUUID(string: UUIDPeripheralServiceString),
      primary: true
    )    
    return service
  }
  
  /// The characteristic used for receiving messages.
  public static var messageCharacteristic: CBMutableCharacteristic {
    CBMutableCharacteristic(
      type: CBUUID(string: UUIDMessageCharacteristicString),
      properties: [.write],
      value: nil,
      permissions: [.writeable]
    )
  }
  
  /// The characteristic used for sending configuration.
  public static func configurationCharacteristic(
    value: Data
  ) -> CBMutableCharacteristic {
    return CBMutableCharacteristic(
      type: CBUUID(
        string: BluetoothService.UUIDConfigurationCharacteristicString
      ),
      properties: [.read],
      value: value,
      permissions: [.readable]
    )
  }
}
