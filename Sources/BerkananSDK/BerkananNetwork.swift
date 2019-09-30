//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
#if canImport(Combine)
import Combine
#endif
import CoreBluetooth

public protocol BerkananNetworkDelegate: class {
  
  func didReceive(_ message: PublicBroadcastMessage)
}

public class BerkananNetwork: NSObject {
  
  public static let shared = BerkananNetwork()
  
  public weak var delegate: BerkananNetworkDelegate?
  
  #if canImport(Combine)
  @available(OSX 10.15, iOS 13.0, *)
  lazy public private(set) var publicBroadcastMessageSubject =
    PassthroughSubject<PublicBroadcastMessage, Never>()
  #endif
  
  @objc dynamic public var numberOfNearbyUsers: Int = 0
  
  public var isStarted: Bool { BluetoothController.shared.isStarted }
  
  @objc dynamic public var bluetoothAuthorization: BluetoothAuthorization =
    .notDetermined
  
  public func start() {
    BluetoothController.shared.start()
  }
  
  public func stop() {
    BluetoothController.shared.stop()
  }
  
  public func broadcast(_ text: String) {
    self.broadcast(PublicBroadcastMessage(text: text))
  }
  
  public func broadcast(_ message: PublicBroadcastMessage) {
    BluetoothController.shared.send(message)
  }
}

@objc public enum BluetoothAuthorization: Int {
  
  case notDetermined
  
  case restricted
  
  case denied
  
  case allowedAlways
  
  @available(iOS, introduced: 7.0, deprecated: 13.0,
  message: "Use CBManagerAuthorization instead")
  @available(macCatalyst, introduced: 13.0, deprecated: 13.0,
  message: "Use CBManagerAuthorization instead")
  public init?(
    cbPeripheralManagerAuthorizationStatus:
    CBPeripheralManagerAuthorizationStatus
  ) {
    self.init(rawValue: cbPeripheralManagerAuthorizationStatus.rawValue)
  }
  
  @available(iOS 13.0, OSX 10.15, *)
  public init?(cbManagerAuthorization: CBManagerAuthorization) {
    self.init(rawValue: cbManagerAuthorization.rawValue)
  }
}
