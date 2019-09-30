//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import SwiftProtobuf
#if canImport(UIKit)
import UIKit.UIDevice
#endif

extension User {
  
  /// The current user.
  public static var current: User = {        
    return User.with {
      #if canImport(UIKit)
      $0.uuid = UIDevice.current.identifierForVendor
      $0.name = UIDevice.current.name
      #endif
    }
  }()
  
  /// The formatted name of the user.
  public var displayName: String {
    return name.isEmpty ? "Nameless" : name
  }
}
