//
//  Created by Zsombor Szabo on 08/11/2019.
//  
//

import Foundation
import SwiftProtobuf

extension Configuration {
  
  /// Initializes `self` with `identifier` and `userInfo`.
  /// 
  /// - Parameter identifier: The identifier used to initialize `self` with.
  public init(identifier: UUID, userInfo: Data? = nil) {
    self.identifier = identifier.protobufValue()
    self.userInfo = userInfo ?? SwiftProtobuf.Internal.emptyData
  }
  
  /// Returns true if `self` is valid.
  public func isValid() -> Bool {
    // Identifier field is required
    if !self.identifier.isValid() {
      return false
    }
    return true
  }
}
