//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

import Foundation
import CoreBluetooth
#if os(watchOS) || os(tvOS)
import CBerkananSDK
#endif

extension BluetoothService {
  
  /// The length in bytes for a characteristic's value.
  public static let maxCharacteristicValueLength = 512
  
  /// The peripheral service to be added to the local GATT database.
  public static var peripheralService: CBMutableService {
    #if os(watchOS) || os(tvOS)
    let service = CBMutableService(
      berkananSDKWithType: CBUUID(string: UUIDPeripheralServiceString),
      primary: true
    )
    #else
    let service = CBMutableService(
      type: CBUUID(string: UUIDPeripheralServiceString),
      primary: true
    )
    #endif
    return service
  }
  
  /// The characteristic used for receiving messages.
  public static var messageCharacteristic: CBMutableCharacteristic {
    #if os(watchOS) || os(tvOS)
    return CBMutableCharacteristic(
      berkananSDKWithType: CBUUID(string: UUIDMessageCharacteristicString),
      properties: [.write],
      value: nil,
      permissions: [.writeable]
    )
    #else
    return CBMutableCharacteristic(
      type: CBUUID(string: UUIDMessageCharacteristicString),
      properties: [.write],
      value: nil,
      permissions: [.writeable]
    )
    #endif
  }
  
  /// The characteristic used for sending configuration.
  public static func configurationCharacteristic(
    value: Data
  ) -> CBMutableCharacteristic {
    #if os(watchOS) || os(tvOS)
    return CBMutableCharacteristic(
      berkananSDKWithType: CBUUID(
        string: BluetoothService.UUIDConfigurationCharacteristicString
      ),
      properties: [.read],
      value: value,
      permissions: [.readable]
    )
    #else
    return CBMutableCharacteristic(
         type: CBUUID(
           string: BluetoothService.UUIDConfigurationCharacteristicString
         ),
         properties: [.read],
         value: value,
         permissions: [.readable]
       )
    #endif
  }
}
