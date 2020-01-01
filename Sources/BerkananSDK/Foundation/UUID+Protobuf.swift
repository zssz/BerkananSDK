//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation

extension UUID {
  
  /// Returns a PBUUID instance with its `value ` set based on `self`.
  public func protobufValue() -> PBUUID {
    .with { $0.value = self.dataRepresentation }
  }
}
