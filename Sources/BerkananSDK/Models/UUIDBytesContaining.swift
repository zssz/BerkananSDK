//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import SwiftProtobuf
import BerkananFoundation

public protocol UUIDBytesContaining {
  
  var uuidBytes: Data { get set }
  
  var uuid: UUID? { get set }    
}

extension UUIDBytesContaining {
  
  public var uuid: UUID? {
    get {
      return try? UUID(dataRepresentation: uuidBytes)
    }
    set {
      uuidBytes = newValue?.dataRepresentation ??
        SwiftProtobuf.Internal.emptyData
    }
  }
}
