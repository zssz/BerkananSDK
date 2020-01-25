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
import SwiftProtobuf

/// A protocol defining methods that local Berkanan Bluetooth service instances call on their delegates to
/// handle events like receiving messages.
public protocol BerkananBluetoothServiceDelegate: class {
  
  /// Tells the delegate that the local Berkanan Bluetooth `service` discovered `remoteService` with
  /// its `configuration` set, and added it to its `servicesInRange`.
  ///
  /// Observe changes to `rssi` of `remoteService` to see how strong its signal is.
  ///
  /// - Parameters:
  ///   - service: The local service that discovered the `remoteService`.
  ///   - remoteService: The remote service discovered by the local `service`.
  func berkananBluetoothService(
    _ service: BerkananBluetoothService,
    didDiscover remoteService: BerkananBluetoothService
  )
  
  /// Tells the delegate that the local Berkanan Bluetooth `service` received a `message`.
  ///
  /// - Parameters:
  ///   - service: The local service that received the `message`.
  ///   - message: The received message by the local `service`.
  func berkananBluetoothService(
    _ service: BerkananBluetoothService,
    didReceive message: Message
  )
}

/// An object that represents a Berkanan Bluetooth service hosted by an app running
/// on the local or a remote device.
///
/// Note: A device can have multiple apps hosting multiple services (typically one) at the
/// same time.
///
/// Initialize a local service with `isLocal` set to true and your `configuration`,
/// then `start()` it.  Use the delegate methods and the Combine-based API to handle
/// events like receiving messages.
///
/// Construct a `Message` with your small data set as its `payload` and send it
/// using the `send(_:via:broadcastTimeToLive:)` method. When a `Message` is
/// received by a service, it automatically sends a copy of it with `timeToLive`
/// field decreased by 1 to its remote services in range, if it didn't see the
/// message before by examining the `identifier` and `timeToLive` is greater than 0.
///
/// Be prepared to receive messages that your app doesn't know how to handle —
/// examine the `payloadType` of the received `Message`.
public class BerkananBluetoothService: NSObject {
  
  /// The delegate assigned with this object.
  ///
  /// Note: Events are not delivered on the main thread.
  public weak var delegate: BerkananBluetoothServiceDelegate?
  
  #if canImport(Combine)
  
  /// Combine version of the `berkananBluetoothService(_:didDiscover:)` delegate method.
  ///
  /// Note: Events are not delivered on the main thread.
  @available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  lazy public private(set) var discoverServiceSubject =
    PassthroughSubject<BerkananBluetoothService, Never>()
  
  /// Convenience publisher to keep track of the number of services in range.
  ///
  /// Note: Events are not delivered on the main thread.
  @available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  lazy public private(set) var numberOfServicesInRangeSubject =
    PassthroughSubject<Int, Never>()
  
  /// Combine version of the `berkananBluetoothService(_:didReceive:)` delegate method.
  ///
  /// Note: Events are not delivered on the main thread.
  @available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
  lazy public private(set) var receiveMessageSubject =
    PassthroughSubject<Message, Never>()
  
  #endif
  
  /// The RSSI of the remote service updated by the local service while in the foreground. If nil then the
  /// remote service is out of range.
  public internal(set) var rssi: NSNumber?
  
  /// The set of previously discovered remote services in range (their `rssi` is not nil) to the local service.
  public internal(set) var servicesInRange = Set<BerkananBluetoothService>() {
    didSet {
      #if canImport(Combine)
      if #available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
        self.numberOfServicesInRangeSubject.send(servicesInRange.count)
      }
      #endif
    }
  }
  
  /// Returns true if the local service is started.
  public var isStarted: Bool { self.bluetoothController?.isStarted ?? false }
  
  /// The Bluetooth authorization status of the local service.
  public var bluetoothAuthorization: BluetoothAuthorization =
    .notDetermined
  
  /// The controller used for Bluetooth communication by the local service internally.
  private var bluetoothController: BluetoothController?
  
  /// The `CBPeripheral` device hosting the remote service.
  public internal(set) weak var peripheral: CBPeripheral?
  
  /// Returns whether `self` is a local service.
  public private(set) var isLocal: Bool
  
  /// The configuration of the service.
  private var configuration: Configuration
  
  /// Sets the `configuration` of the service.
  ///
  /// - Parameter configuration: The configuration to set for the service.
  /// - Throws: `CBATTError(.invalidPdu)` if `self.isLocal` and `configuration` is
  ///     invalid or its PDU representation is too big.
  public func setConfiguration(_ configuration: Configuration) throws {
    if self.isLocal {
      try self.bluetoothController?.setConfiguration(configuration)
    }
    self.configuration = configuration
  }
  
  /// Returns the configuration of the service.
  public func getConfiguration() -> Configuration { self.configuration }
  
  /// Initializes `self` with `isLocal` and `configuration`.
  ///
  /// - Parameters:
  ///   - isLocal: The boolean `isLocal` state to initialize `self` with.
  ///   - configuration: The configuration to initialize `self` with.
  /// - Throws: `CBATTError(.invalidPdu)` if `self.isLocal` and `configuration` is
  ///     invalid or its PDU representation is too big.
  public init(
    isLocal: Bool = true,
    configuration: Configuration = .with { $0.identifier = PBUUID.random() }    
  ) throws {
    self.isLocal = isLocal
    self.configuration = configuration
    if isLocal {
      self.bluetoothController =
        try BluetoothController(configuration: configuration)
    }
    super.init()
    self.bluetoothController?.service = self
  }
  
  /// Starts the local service. No-op if `isLocal` is false.
  public func start() {
    self.bluetoothController?.start()
  }
  
  /// Stops the local service. No-op if `isLocal` is false.
  public func stop() {
    self.bluetoothController?.stop()
  }
  
  /// Sends `message`.
  ///
  /// If app is in background or `services` is nil or empty or any of its members is
  /// out of range (its `rssi` is nil) then a copy of `message` with its time to live
  /// field set to `timeToLive` is sent to `self.servicesInRange`. No-op if
  /// `self.isLocal` is false.
  ///
  /// Internally this uses a [flooding
  /// algorithm](https://en.wikipedia.org/wiki/Flooding_(computer_networking)) . Use
  /// `services` and `message.timeToLive` to limit the number of duplicated messages.
  ///
  /// Delivery of `message` is best-effort and not guaranteed. Your app is repsonsible
  /// for sending back ack type messages, if needed.
  ///
  /// - Parameters:
  ///   - message: The message to send via `services`.
  ///   - services: The services to send the `message` via.
  ///   - timeToLive: The value of the time to live field of the copy of `message` in the case of it
  ///       being broadcasted to all `self.servicesInRange`.
  /// - Throws: `CBATTError(.invalidPdu)`  if `self.isLocal` and `message` is invalid or
  ///     its PDU representation is too big.
  public func send(
    _ message: Message,
    via services: [BerkananBluetoothService]? = nil,
    broadcastTimeToLive timeToLive: Int32 = Message.timeToLiveDefault
  ) throws {
    guard self.isLocal else { return }
    if !message.isValid() || message.isPDUTooBig() {
      throw CBATTError(.invalidPdu)
    }
    self.bluetoothController?.send(
      message, via: services, broadcastTimeToLive: timeToLive
    )
  }
}

public enum BluetoothAuthorization: Int {
  
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
  
  @available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
  public init?(cbManagerAuthorization: CBManagerAuthorization) {
    self.init(rawValue: cbManagerAuthorization.rawValue)
  }
}
