//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

import Foundation
import SwiftProtobuf

extension Message {
  
  /// The default value used for `timeToLive`.
  public static let timeToLiveDefault: Int32 = 15
  
  public init(
    payloadType: UUID? = nil, payload: Data?,
    timeToLive: Int32 = Message.timeToLiveDefault,
    from sourceAddress: UUID? = nil,
    to destinationAddress: UUID? = nil
  ) {
    self.init(
      payloadType: payloadType?.protobufValue(), payload: payload,
      timeToLive: timeToLive, from: sourceAddress?.protobufValue(),
      to: destinationAddress?.protobufValue())
  }
  
  public init(
    payloadType: PBUUID? = nil, payload: Data?,
    timeToLive: Int32 = Message.timeToLiveDefault,
    from sourceAddress: PBUUID? = nil,
    to destinationAddress: PBUUID? = nil
  ) {
    self.identifier = PBUUID.random()
    self.timeToLive = timeToLive
    if let sourceAddress = sourceAddress {
      self.sourceAddress = sourceAddress
    }
    if let destinationAddress = destinationAddress {
      self.destinationAddress = destinationAddress
    }
    if let payloadType = payloadType {
      self.payloadType = payloadType
    }
    self.payload = payload ?? SwiftProtobuf.Internal.emptyData
  }
  
  /// Returns true if `self` is valid.
  public func isValid() -> Bool {
    // Identifier field is required
    if !self.identifier.isValid() {
      return false
    }
    if !self.sourceAddress.value.isEmpty && !self.sourceAddress.isValid() {
      return false
    }
    if !self.destinationAddress.value.isEmpty
      && !self.destinationAddress.isValid() {
      return false
    }
    if !self.payloadType.value.isEmpty && !self.payloadType.isValid() {
      return false
    }
    return true
  }
}
