//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import Compression
import BerkananCompression
import CoreBluetooth.CBError

extension Message {
  
  /// Initializes `self` with `pdu` representation, which is expected to be a serialized `Message`
  /// instance compressed using ZLIB algorithm.
  ///
  /// - Parameter pdu: The PDU representation to initialize `self` with.
  /// - Throws: `CBATTError(.invalidPdu)` or `SwiftProtobuf.BinaryDecodingError` if
  ///     `pdu` is not in the expected format.
  public init?(pdu: Data) throws {
    var data: Data? = pdu
    data = data?.decompressed(using: COMPRESSION_ZLIB)
    guard let result = data else {
      throw CBATTError(.invalidPdu)
    }
    try self.init(serializedData: result)
  }
  
  /// Returns the PDU representation of `self`, which is `self` serialized and compressed using ZLIB
  /// algorithm.
  ///
  /// - Throws: `SwiftProtobuf.BinaryEncodingError` or `CBATTError(.invalidPdu)` if
  ///     there was an error during serialization or compression.
  public func pdu() throws -> Data {
    var data: Data?
    data = try self.serializedData()
    data = data?.compressed(using: COMPRESSION_ZLIB)
    guard let result = data else {
      throw CBATTError(.invalidPdu)
    }
    return result
  }
  
  /// Returns true if the PDU representation of `self` is too big for sending.
  ///
  /// - SeeAlso: `BluetoothService.maxCharacteristicValueLength`
  public func isPDUTooBig() -> Bool {
    return availablePDULength() < 0
  }
  
  /// Returns the number of bytes available until the PDU representation of `self` would be too big for
  /// sending.
  ///
  /// - SeeAlso: `BluetoothService.maxCharacteristicValueLength`
  public func availablePDULength() -> Int {
    let pduLength: Int = (try? self.pdu().count) ?? 0
    return BluetoothService.maxCharacteristicValueLength - pduLength
  }
}
