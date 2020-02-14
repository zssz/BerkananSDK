//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit.UIDevice
#endif

extension User {
  
  /// Returns the current user.
  ///
  /// On systems with UIKit it uses `UIDevice.current.identifierForVendor` for `identifier`
  /// and `UIDevice.current.name` for `name`.
  public static var current: User = {        
    return .with {
      #if canImport(UIKit) && !os(watchOS)
      $0.identifier =
        UIDevice.current.identifierForVendor?.protobufValue() ?? PBUUID.random()
      $0.name = UIDevice.current.name
      #endif
    }
  }()
  
  /// Returns the display name of `self`. If `name` is empty then it returns `"Nameless"`.
  public var displayName: String {
    return self.name.isEmpty ? "Nameless" : self.name
  }
}
