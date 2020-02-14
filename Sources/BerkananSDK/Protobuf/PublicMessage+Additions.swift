//
// Copyright © 2019-2020 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.md for license information.
//

import Foundation

extension PublicMessage {
  
  /// Initializes `self` with `text`, a random UUID for `identifier` and `User.current` for
  /// `sourceUser`.
  /// 
  /// - Parameter text: The text used to initialize `self` with.
  public init(text: String) {
    self.identifier = PBUUID.random()
    self.sourceUser = User.current
    self.text = text
  }  
}
