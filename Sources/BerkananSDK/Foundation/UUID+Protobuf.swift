//
//  Created by Zsombor Szabo on 07/11/2019.
//  
//

import Foundation

extension UUID {
  
  /// Returns a PBUUID instance with its `value ` set based on `self`.
  public func protobufValue() -> PBUUID {
    .with { $0.value = self.dataRepresentation }
  }
}
