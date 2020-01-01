//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation

extension PBUUID {
  
  /// The payload type identifier used when notifying services in range when the configuration of the local
  /// service was updated.
  static let updatedConfiguration =
    UUID(uuidString: "90500473-2FE5-4B65-AA4E-1EFD61063E16")!.protobufValue()
  
  /// The `payloadType` identifier when using `PublicMessage` as the `payload` of a `Message`.
  public static let publicMessage: PBUUID =
    UUID(uuidString: "6113B8CC-6D42-4AA6-83F1-98B81752A698")!.protobufValue()
}
