//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import BerkananFoundation

extension PBUUID {
  
  /// Returns a random and valid `PBUUID` instance.
  public static func random() -> PBUUID {
    return .with { $0.value = UUID().dataRepresentation }
  }
  
  /// Returns the `UUID` representation of `self`, if valid.
  public func foundationValue() -> UUID? {
    return try? UUID(dataRepresentation: self.value)
  }
  
  /// Returns true if `self` is valid.
  public func isValid() -> Bool {    
    return (self.foundationValue() != nil)
  }
}
