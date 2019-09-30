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

extension PublicBroadcastMessage {
  
  public init?(pdu: Data) throws {
    var data: Data?
    data = pdu
    data = data?.decompressed(using: COMPRESSION_ZLIB)        
    guard let result = data else {
      throw CBATTError(.invalidPdu)
    }
    try self.init(serializedData: result)
  }
  
  public func pdu() throws -> Data {
    var data: Data?
    data = try self.serializedData()
    data = data?.compressed(using: COMPRESSION_ZLIB)
    guard let result = data else {
      throw CBATTError(.invalidPdu)
    }
    return result
  }
  
  public static func isPDUTooBig(for text: String) -> Bool {
    let message = PublicBroadcastMessage(text: text)
    let data = try? message.pdu()
    return data?.count ?? 0 > BerkananService.maxCharacteristicWriteValueLength
  }
}
