//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import SwiftProtobuf

extension PublicBroadcastMessage {
  
  public static let timeToLiveDefault: Int32 = 15
  
  public init(text: String) {
    self.uuid = UUID()
    self.timeToLive = PublicBroadcastMessage.timeToLiveDefault
    self.sourceUser = User.current
    self.text = text
  }
  
  public var text: String? {
    get {
      return String(bytes: self.payload, encoding: .utf8)
    }
    set {
      self.payload = newValue?.data(using: .utf8) ??
        SwiftProtobuf.Internal.emptyData
    }
  }
}
