//
//  Created by Zsombor Szabo on 07/11/2019.
//  
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
