//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import CoreBluetooth
#if canImport(UIKit) && !os(watchOS)
import UIKit.UIApplication
#endif
import os.log
#if os(watchOS) || os(tvOS)
import CBerkananSDK
#endif

extension TimeInterval {
  
  public static let peripheralDiscoveryTimeout: TimeInterval = 12
  public static let peripheralConnectingTimeout: TimeInterval = 5
  public static let peripheralConnectionTimeout: TimeInterval = 3
}

/// The controller responsible for the Bluetooth communication.
class BluetoothController: NSObject {
  
  public let label = UUID().uuidString
  
  @available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *)
  lazy private var log = OSLog(subsystem: label, category: "BerkananSDK")
  
  lazy private var dispatchQueue: DispatchQueue =
    DispatchQueue(label: label, qos: .userInteractive)
  
  weak var service: BerkananBluetoothService?
  
  private var centralManager: CBCentralManager?
  
  private var discoveredPeripherals = Set<CBPeripheral>()
  
  private var discoveredPeripheralsWithBerkananServices: Set<CBPeripheral> {
    #if targetEnvironment(macCatalyst)
    var result = Set<CBPeripheral>()
    self.servicesOfPeripherals.forEach {
      if !$0.value.isEmpty {
        result.insert($0.key)
      }
    }
    return result
    #else
    return discoveredPeripherals
    #endif
  }
  
  private var discoveryTimeoutTimersForPeripheralIdentifiers =
    [UUID : Timer]()
  private var connectingTimeoutTimersForPeripheralIdentifiers =
    [UUID : Timer]()
  private var connectionTimeoutTimersForPeripheralIdentifiers =
    [UUID : Timer]()
  
  private var connectedPeripherals = Set<CBPeripheral>() {
    didSet {
      self.handleConnectedPeripheralsChange()
    }
  }
  
  #if os(watchOS) || os(tvOS)
  private static let maxNumberOfConcurrentPeripheralConnections = 2
  #else
  private static let maxNumberOfConcurrentPeripheralConnections = 5
  #endif
  
  private var messagesForPeripherals =
    [CBPeripheral : [Message]]()
  
  private var seenMessageUUIDs =
    NSMutableOrderedSet(capacity: seenMessageUUIDsCacheLimit)
  
  private static let seenMessageUUIDsCacheLimit = 1024
  
  private var peripheralManager: CBPeripheralManager?
  
  private var configuration: Configuration!
  
  public func setConfiguration(_ configuration: Configuration) throws {
    if !configuration.isValid() || configuration.isPDUTooBig() {
      throw CBATTError(.invalidPdu)
    }
    self.dispatchQueue.async {
      self.configuration = configuration
      if self.isStarted {
        if let peripheralManager = self.peripheralManager {
          self._peripheralManagerDidUpdateState(peripheralManager)
        }
        let message = Message(
          payloadType: .updatedConfiguration,
          payload: nil,          
          timeToLive: 0
        )        
        self._send(message)
      }
    }
  }
  
  private var servicesOfPeripherals =
    [CBPeripheral : Set<BerkananBluetoothService>]()
    
  private var rssiOfPeripherals = [CBPeripheral : NSNumber?]()
  
  private var peripheralsToReadConfigurationsFrom = Set<CBPeripheral>()
  
  private var peripheralsToConnect: Set<CBPeripheral> {
    return Set(messagesForPeripherals.keys)
      .union(peripheralsToReadConfigurationsFrom)
  }
  
  private func handleConnectedPeripheralsChange() {
    #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(watchOS)
    if self.connectedPeripherals.isEmpty {
      self.endBackgroundTaskIfNeeded()
    }
    else {
      self.beginBackgroundTaskIfNeeded()
    }
    #endif
  }
  
  // macCatalyst apps do not need background tasks.
  // watchOS apps do not have background tasks.
  #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(watchOS)
  private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?
  
  private func beginBackgroundTaskIfNeeded() {
    guard self.backgroundTaskIdentifier == nil else { return }
    self.backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log("Did expire background task", log: self.log)
      }
      self.endBackgroundTaskIfNeeded()
    }
  }
  
  private func endBackgroundTaskIfNeeded() {
    if let identifier = self.backgroundTaskIdentifier {
      self.backgroundTaskIdentifier = nil
      UIApplication.shared.endBackgroundTask(identifier)
    }
  }
  #endif
  
  init(configuration: Configuration) throws {
    super.init()
    try self.setConfiguration(configuration)
    // macCatalyst apps do not need background support.
    // watchOS apps do not have background tasks.
    #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(watchOS)
    let notificationCenter = NotificationCenter.default
    notificationCenter.addObserver(
      self,
      selector: #selector(applicationDidEnterBackgroundNotification(_:)),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    notificationCenter.addObserver(
      self,
      selector: #selector(applicationWillEnterForegroundNotification(_:)),
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
    #endif
  }
  
  deinit {
    #if canImport(UIKit) && !targetEnvironment(macCatalyst) && !os(watchOS)
    let notificationCenter = NotificationCenter.default
    notificationCenter.removeObserver(
      self,
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    notificationCenter.removeObserver(
      self,
      name: UIApplication.willEnterForegroundNotification,
      object: nil
    )
    #endif
  }
  
  // MARK: - Notifications
  
  @objc func applicationDidEnterBackgroundNotification(
    _ notification: Notification
  ) {
    self.dispatchQueue.async { [weak self] in
      guard let self = self else { return }
      self.discoveryTimeoutTimersForPeripheralIdentifiers.values.forEach {
        $0.invalidate()
      }
      self.discoveryTimeoutTimersForPeripheralIdentifiers.removeAll()
    }
  }
  
  @objc func applicationWillEnterForegroundNotification(
    _ notification: Notification
  ) {
    self.dispatchQueue.async { [weak self] in
      guard let self = self else { return }
      self.discoveredPeripherals.forEach {
        self.setupDiscoveryTimeoutTimer(for: $0)
      }
    }
  }
  
  // MARK: -
  
  /// Returns true if the service is started.
  var isStarted: Bool {
    return self.centralManager != nil
  }
  
  /// Starts the service.
  func start() {
    self.dispatchQueue.async {
      guard self.centralManager == nil else {
        return
      }
      self.centralManager = CBCentralManager(
        delegate: self,
        queue: self.dispatchQueue,
        options: nil
      )
      #if os(watchOS) || os(tvOS)
      self.peripheralManager = CBPeripheralManager(
        berkananSDKWith: self,
        queue: self.dispatchQueue,
        options: [
          CBPeripheralManagerOptionRestoreIdentifierKey:
            "chat.berkanan.sdk.peripheral." +
              self.configuration.identifier.foundationValue()!.uuidString
      ])
      #else
      self.peripheralManager = CBPeripheralManager(
        delegate: self,
        queue: self.dispatchQueue,
        options: [
          CBPeripheralManagerOptionRestoreIdentifierKey:
            "chat.berkanan.sdk.peripheral." +
              self.configuration.identifier.foundationValue()!.uuidString
      ])
      #endif
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Service (%@) started",
          log: self.log,
          self.configuration.identifier.foundationValue()?.description ?? ""
        )
      }
    }
  }
  
  /// Stops the service.
  func stop() {
    self.dispatchQueue.async {
      self.stopCentralManager()
      self.centralManager?.delegate = nil
      self.centralManager = nil
      self.stopPeripheralManager()
      self.peripheralManager?.delegate = nil
      self.peripheralManager = nil
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Service (%@) stopped",
          log: self.log,
          self.configuration.identifier.foundationValue()?.description ?? ""
        )
      }
    }
  }
  
  private func stopCentralManager() {
    self.discoveryTimeoutTimersForPeripheralIdentifiers.values.forEach {
      $0.invalidate()
    }
    self.discoveryTimeoutTimersForPeripheralIdentifiers.removeAll()
    self.connectingTimeoutTimersForPeripheralIdentifiers.values.forEach {
      $0.invalidate()
    }
    self.connectingTimeoutTimersForPeripheralIdentifiers.removeAll()
    self.connectionTimeoutTimersForPeripheralIdentifiers.values.forEach {
      $0.invalidate()
    }
    self.connectionTimeoutTimersForPeripheralIdentifiers.removeAll()
    self.discoveredPeripherals.forEach { self.flushPeripheral($0) }
    self.discoveredPeripherals.removeAll()
    self.connectedPeripherals.removeAll()
    self.messagesForPeripherals.removeAll()
    self.seenMessageUUIDs.removeAllObjects()
    self.peripheralsToReadConfigurationsFrom.removeAll()
    self.servicesOfPeripherals.removeAll()
    self.service?.servicesInRange.removeAll()
    if self.centralManager?.isScanning ?? false {
      self.centralManager?.stopScan()
    }
  }
  
  private func stopPeripheralManager() {
    if self.peripheralManager?.isAdvertising ?? false {
      self.peripheralManager?.stopAdvertising()
    }
    if self.peripheralManager?.state == .poweredOn {
        self.peripheralManager?.removeAllServices()
    }    
  }
  
  func send(
    _ message: Message,
    via services: [BerkananBluetoothService]? = nil,
    broadcastTimeToLive timeToLive: Int32 = Message.timeToLiveDefault
  ) {
    self.dispatchQueue.async {
      self._send(message, via: services, broadcastTimeToLive: timeToLive)
    }
  }
  
  private func _send(
    _ message: Message,
    via services: [BerkananBluetoothService]? = nil,
    broadcastTimeToLive timeToLive: Int32 = Message.timeToLiveDefault
  ) {
    guard self.discoveredPeripheralsWithBerkananServices.count > 0 else {
      return
    }
    guard let messageUUID = message.identifier.foundationValue() else {
      return
    }
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Enqueued message (uuid=%@ payload='%@')",
        log: self.log,
        messageUUID.description,
        message.payload.description
      )
    }
    self.addToSeenMessageUUIDsIfNeeded(uuid: messageUUID)
    var isInBackground = false
    let actions = {
      if !isInBackground,
        let services = services,
        !services.isEmpty,
        !services.contains(where: { $0.rssi == nil }) {
        services.compactMap({ $0.peripheral }).forEach {
          self.enqueue(message: message, for: $0)
        }
      }
      else {
        var messageCopy = message
        messageCopy.timeToLive = timeToLive
        self.discoveredPeripheralsWithBerkananServices.forEach {
          self.enqueue(message: messageCopy, for: $0)
        }
      }
      self.connectPeripheralsIfNeeded()
    }
    #if canImport(UIKit) && !os(watchOS)
    DispatchQueue.main.async {
      isInBackground = (UIApplication.shared.applicationState == .background)
      self.dispatchQueue.async {
        actions()
      }
    }
    #else
    actions()
    #endif
  }
  
  // MARK: - Private
  
  private func enqueue(message: Message, for peripheral: CBPeripheral) {
    if self.messagesForPeripherals[peripheral] == nil {
      self.messagesForPeripherals[peripheral] = [Message]()
    }
    var messages = self.messagesForPeripherals[peripheral]
    messages?.append(message)
    self.messagesForPeripherals[peripheral] = messages
  }
  
  private func connectPeripheralsIfNeeded() {
    guard self.peripheralsToConnect.count > 0 else {
      return
    }
    guard self.connectedPeripherals.count <
      BluetoothController.maxNumberOfConcurrentPeripheralConnections else {
        return
    }
    let disconnectedPeripherals = self.peripheralsToConnect.filter {
      $0.state == .disconnected || $0.state == .disconnecting
    }
    disconnectedPeripherals.prefix(
      BluetoothController.maxNumberOfConcurrentPeripheralConnections -
        self.connectedPeripherals.count
    ).forEach {
      self.connectIfNeeded(peripheral: $0)
    }
  }
  
  private func connectIfNeeded(peripheral: CBPeripheral) {
    guard let centralManager = centralManager else {
      return
    }
    if peripheral.state != .connected {
      if peripheral.state != .connecting {
        self.centralManager?.connect(peripheral, options: nil)
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
          os_log(
            "Central manager connecting peripheral (uuid=%@ name='%@')",
            log: self.log,
            peripheral.identifier.description,
            peripheral.name ?? ""
          )
        }
        self.setupConnectingTimeoutTimer(for: peripheral)
        self.connectedPeripherals.insert(peripheral)
      }
    }
    else {
      self._centralManager(centralManager, didConnect: peripheral)
    }
  }
  
  private func addToSeenMessageUUIDsIfNeeded(uuid: UUID) {
    if !self.seenMessageUUIDs.contains(uuid) {
      if self.seenMessageUUIDs.count >=
        BluetoothController.seenMessageUUIDsCacheLimit {
        self.seenMessageUUIDs.removeObject(at: 0)
      }
      self.seenMessageUUIDs.add(uuid)
    }
  }
  
  private func setupDiscoveryTimeoutTimer(for peripheral: CBPeripheral) {
    let timer = Timer.init(
      timeInterval: .peripheralDiscoveryTimeout,
      target: self,
      selector: #selector(_discoveryTimeoutTimerFired(timer:)),
      userInfo: ["peripheral" : peripheral],
      repeats: false
    )
    timer.tolerance = 0.5
    RunLoop.main.add(timer, forMode: .common)
    self.discoveryTimeoutTimersForPeripheralIdentifiers[peripheral.identifier]?
      .invalidate()
    self.discoveryTimeoutTimersForPeripheralIdentifiers[peripheral.identifier] =
    timer
  }
  
  private func setupConnectingTimeoutTimer(for peripheral: CBPeripheral) {
    let timer = Timer.init(
      timeInterval: .peripheralConnectingTimeout,
      target: self,
      selector: #selector(_connectingTimeoutTimerFired(timer:)),
      userInfo: ["peripheral" : peripheral],
      repeats: false
    )
    timer.tolerance = 0.5
    RunLoop.main.add(timer, forMode: .common)
    self.connectingTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier]?.invalidate()
    self.connectingTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier] = timer
  }
  
  private func setupConnectionTimeoutTimer(for peripheral: CBPeripheral) {
    let timer = Timer.init(
      timeInterval: .peripheralConnectionTimeout,
      target: self,
      selector: #selector(_connectionTimeoutTimerFired(timer:)),
      userInfo: ["peripheral" : peripheral],
      repeats: false
    )
    timer.tolerance = 0.5
    RunLoop.main.add(timer, forMode: .common)
    self.connectionTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier]?.invalidate()
    self.connectionTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier] = timer
  }
  
  @objc private func _discoveryTimeoutTimerFired(timer: Timer) {
    let userInfo = timer.userInfo
    self.dispatchQueue.async { [weak self] in
      guard let self = self else { return }
      guard let userInfo = userInfo as? [AnyHashable : Any],
        let peripheral = userInfo["peripheral"] as? CBPeripheral else {
          return
      }
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Discovering did time out for peripheral (uuid=%@ name='%@')",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? ""
        )
      }
      self.flushPeripheral(peripheral)
    }
  }
  
  @objc private func _connectingTimeoutTimerFired(timer: Timer) {
    let userInfo = timer.userInfo
    self.dispatchQueue.async { [weak self] in
      guard let self = self else { return }
      guard let userInfo = userInfo as? [AnyHashable : Any],
        let peripheral = userInfo["peripheral"] as? CBPeripheral else {
          return
      }
      if peripheral.state != .connected {
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
          os_log(
            "Connecting did time out for peripheral (uuid=%@ name='%@')",
            log: self.log,
            peripheral.identifier.description,
            peripheral.name ?? ""
          )
        }
        #if targetEnvironment(macCatalyst)
        if !(self.servicesOfPeripherals[peripheral]?.isEmpty ?? true) {
          self.flushPeripheral(peripheral)
        }
        else {
          self.cancelConnectionIfNeeded(for: peripheral)
        }
        #else
        self.flushPeripheral(peripheral)
        #endif
      }
    }
  }
  
  @objc private func _connectionTimeoutTimerFired(timer: Timer) {
    let userInfo = timer.userInfo
    self.dispatchQueue.async { [weak self] in
      guard let self = self else { return }
      guard let userInfo = userInfo as? [AnyHashable : Any],
        let peripheral = userInfo["peripheral"] as? CBPeripheral else {
          return
      }
      guard self.hasMessagesEnqueued(for: peripheral) ||
        self.shouldReadConfigurations(from: peripheral) else {
          if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
              "Connection did time out for peripheral (uuid=%@ name='%@')",
              log: self.log,
              peripheral.identifier.description,
              peripheral.name ?? ""
            )
          }
          self.cancelConnectionIfNeeded(for: peripheral)
          return
      }
      // Start over
      self._peripheral(peripheral, didDiscoverServices: nil)
    }
  }
  
  private func flushPeripheral(_ peripheral: CBPeripheral) {
    peripheral.delegate = nil
    self.servicesOfPeripherals[peripheral]?.forEach {
      $0.rssi = nil
    }
    self.rssiOfPeripherals[peripheral] = nil
    if let services = self.servicesOfPeripherals[peripheral] {
      self.service?.servicesInRange.subtract(services)
    }
    self.discoveredPeripherals.remove(peripheral)
    self.discoveryTimeoutTimersForPeripheralIdentifiers[peripheral.identifier]?
      .invalidate()
    self.discoveryTimeoutTimersForPeripheralIdentifiers[peripheral.identifier] =
    nil
    self.servicesOfPeripherals.removeValue(forKey: peripheral)
    self.cancelConnectionIfNeeded(for: peripheral)
  }
  
  private func cancelConnectionIfNeeded(for peripheral: CBPeripheral) {
    self.connectingTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier]?.invalidate()
    self.connectingTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier] = nil
    self.connectionTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier]?.invalidate()
    self.connectionTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier] = nil
    if peripheral.state != .disconnected {
      self.centralManager?.cancelPeripheralConnection(peripheral)
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Central manager cancelled peripheral (uuid=%@ name='%@') connection",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? ""
        )
      }
    }
    self.peripheralsToReadConfigurationsFrom.remove(peripheral)
    self.messagesForPeripherals.removeValue(forKey: peripheral)
    self.connectedPeripherals.remove(peripheral)
    self.connectPeripheralsIfNeeded()
  }
}

extension BluetoothController: CBCentralManagerDelegate {
  
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Central manager did update state=%@",
        log: self.log,
        String(describing: central.state.rawValue)
      )
    }
    self.stopCentralManager()
    switch central.state {
      case .poweredOn:
        #if targetEnvironment(macCatalyst)
        // CoreBluetooth on macCatalyst doesn't discover services of iOS apps
        // running in the background. Therefore we scan for everything.
        let services: [CBUUID]? = nil
        #else
        let services = [
          CBUUID(string: BluetoothService.UUIDPeripheralServiceString)
        ]
        #endif
        central.scanForPeripherals(
          withServices: services,
          options: [CBCentralManagerScanOptionAllowDuplicatesKey :
            NSNumber(booleanLiteral: true)]
        )
        #if targetEnvironment(macCatalyst)
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
          os_log(
            "Central manager scanning for peripherals with services=%@",
            log: self.log,
            services ?? ""
          )
        }
        #else
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
          os_log(
            "Central manager scanning for peripherals with services=%@",
            log: self.log,
            services
          )
        }
      #endif
      default:
        ()
    }
  }
  
  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String : Any],
    rssi RSSI: NSNumber
  ) {
    if !self.discoveredPeripherals.contains(peripheral) {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Central manager did discover new peripheral (uuid=%@ name='%@') RSSI=%d",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? "",
          RSSI.intValue
        )
      }
      self.peripheralsToReadConfigurationsFrom.insert(peripheral)
    }
    self.discoveredPeripherals.insert(peripheral)
    self.servicesOfPeripherals[peripheral]?.forEach {
      $0.rssi = RSSI
    }
    self.rssiOfPeripherals[peripheral] = RSSI
    if let services = self.servicesOfPeripherals[peripheral] {
      if let service = self.service {
        if service.servicesInRange.union(services).count !=
          service.servicesInRange.count {
          service.servicesInRange.formUnion(services)
        }
      }
    }
    self.connectPeripheralsIfNeeded()
    #if canImport(UIKit) && !os(watchOS)
    DispatchQueue.main.async {
      guard UIApplication.shared.applicationState != .background else {
        return
      }
      self.dispatchQueue.async {
        self.setupDiscoveryTimeoutTimer(for: peripheral)
      }
    }
    #else
    self.setupDiscoveryTimeoutTimer(for: peripheral)
    #endif
  }
  
  func centralManager(
    _ central: CBCentralManager,
    didConnect peripheral: CBPeripheral
  ) {
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Central manager did connect peripheral (uuid=%@ name='%@')",
        log: self.log,
        peripheral.identifier.description,
        peripheral.name ?? ""
      )
    }
    self.connectingTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier]?.invalidate()
    self.connectingTimeoutTimersForPeripheralIdentifiers[
      peripheral.identifier] = nil
    self._centralManager(central, didConnect: peripheral)
  }
  
  func _centralManager(
    _ central: CBCentralManager,
    didConnect peripheral: CBPeripheral
  ) {
    peripheral.delegate = self
    if peripheral.services == nil {
      let services = [
        CBUUID(string: BluetoothService.UUIDPeripheralServiceString)
      ]
      peripheral.discoverServices(services)
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') discovering services=%@",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? "",
          services)
      }
    }
    else {
      self._peripheral(peripheral, didDiscoverServices: nil)
    }
  }
  
  func centralManager(
    _ central: CBCentralManager,
    didFailToConnect peripheral: CBPeripheral,
    error: Error?
  ) {
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Central manager did fail to connect peripheral (uuid=%@ name='%@') error=%@",
        log: self.log,
        type:.error,
        peripheral.identifier.description,
        peripheral.name ?? "",
        error as CVarArg? ?? ""
      )
    }
    self.cancelConnectionIfNeeded(for: peripheral)
  }
  
  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Central manager did disconnect peripheral (uuid=%@ name='%@') error=%@",
          log: self.log,
          type:.error,
          peripheral.identifier.description,
          peripheral.name ?? "",
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Central manager did disconnect peripheral (uuid=%@ name='%@')",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? ""
        )
      }
    }
    self.cancelConnectionIfNeeded(for: peripheral)
  }
}

extension BluetoothController: CBPeripheralDelegate {
  
  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverServices error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did discover services error=%@",
          log: self.log,
          type:.error,
          peripheral.identifier.description,
          peripheral.name ?? "",
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did discover services",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? ""
        )
      }
    }
    self._peripheral(peripheral, didDiscoverServices: error)
  }
  
  func _peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverServices error: Error?
  ) {
    guard error == nil, let services = peripheral.services,
      services.count > 0 else {
        self.cancelConnectionIfNeeded(for: peripheral)
        return
    }
    let servicesWithCharacteristicsToDiscover = services.filter {
      $0.characteristics == nil
    }
    if servicesWithCharacteristicsToDiscover.count == 0 {
      self.startTransfers(for: peripheral)
    }
    else {
      servicesWithCharacteristicsToDiscover.forEach { service in
        let characteristics = [
          CBUUID(string: BluetoothService.UUIDMessageCharacteristicString),
          CBUUID(string: BluetoothService.UUIDConfigurationCharacteristicString)
        ]
        peripheral.discoverCharacteristics(characteristics, for: service)
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
          os_log(
            "Peripheral (uuid=%@ name='%@') discovering characteristics=%@ for service=%@",
            log: self.log,
            peripheral.identifier.description,
            peripheral.name ?? "",
            characteristics.description,
            service.description
          )
        }
      }
    }
  }
  
  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did discover characteristics for service=%@ error=%@",
          log: self.log,
          type:.error,
          peripheral.identifier.description,
          peripheral.name ?? "",
          service.description,
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did discover characteristics for service=%@",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? "",
          service.description
        )
      }
    }
    guard error == nil, let services = peripheral.services else {
      self.cancelConnectionIfNeeded(for: peripheral)
      return
    }
    let servicesWithCharacteristicsToDiscover = services.filter {
      $0.characteristics == nil
    }
    if servicesWithCharacteristicsToDiscover.count == 0 {
      self.startTransfers(for: peripheral)
    }
  }
  
  private func hasMessagesEnqueued(for peripheral: CBPeripheral) -> Bool {
    return (self.messagesForPeripherals[peripheral]?.count ?? 0) > 0
  }
  
  private func shouldReadConfigurations(from peripheral: CBPeripheral) -> Bool {
    return self.peripheralsToReadConfigurationsFrom.contains(peripheral)
  }
  
  private func startTransfers(for peripheral: CBPeripheral) {
    guard let services = peripheral.services else {
      self.cancelConnectionIfNeeded(for: peripheral)
      return
    }
    services.forEach { service in
      self._peripheral(
        peripheral,
        didDiscoverCharacteristicsFor: service,
        error: nil
      )
    }
    self.messagesForPeripherals.removeValue(forKey: peripheral)
    self.setupConnectionTimeoutTimer(for: peripheral)
  }
  
  func _peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard error == nil else {
      self.cancelConnectionIfNeeded(for: peripheral)
      return
    }
    
    // Read configuration, if needed
    if let configurationCharacteristic = service.characteristics?.first(where: {
      $0.uuid == CBUUID(
        string: BluetoothService.UUIDConfigurationCharacteristicString
      )
    }), self.shouldReadConfigurations(from: peripheral) {
      peripheral.readValue(for: configurationCharacteristic)
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') reading value for characteristic=%@ for service=%@",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? "",
          configurationCharacteristic.description,
          service.description
        )
      }
    }
    
    // Send message, if needed
    if let messageCharacteristic = service.characteristics?.first(where: {
      $0.uuid == CBUUID(
        string: BluetoothService.UUIDMessageCharacteristicString
      )
    }), let messages = self.messagesForPeripherals[peripheral],
      messages.count > 0 {
      do {
        for message in messages {
          var data: Data
          // To reduce the number of messages set time to live to 0
          // if the service is not the first in the list. This way only one app
          // will retransmit the message on the remote device.
          if peripheral.services?.firstIndex(of: service) == 0 {
            data = try message.pdu()
          }
          else {
            var messageCopy = message
            messageCopy.timeToLive = 0
            data = try messageCopy.pdu()
          }
          peripheral.writeValue(
            data,
            for: messageCharacteristic,
            type: .withResponse
          )
          if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
            os_log(
              "Peripheral (uuid=%@ name='%@') writing value=%{iec-bytes}d for characteristic=%@ for service=%@",
              log: self.log,
              peripheral.identifier.description,
              peripheral.name ?? "",
              data.count,
              messageCharacteristic.description,
              service.description
            )
          }
        }
      }
      catch {
        self.cancelConnectionIfNeeded(for: peripheral)
      }
    }
  }
  
  func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did write value for characteristic=%@ for service=%@ error=%@",
          log: self.log,
          type:.error,
          peripheral.identifier.description,
          peripheral.name ?? "",
          characteristic.description,
          characteristic.service.description,
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did write value for characteristic=%@ for service=%@",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? "",
          characteristic.description,
          characteristic.service.description
        )
      }
    }
  }
  
  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did update value for characteristic=%@ for service=%@ error=%@",
          log: self.log,
          type:.error,
          peripheral.identifier.description,
          peripheral.name ?? "",
          characteristic.description,
          characteristic.service.description,
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did update value=%{iec-bytes}d for characteristic=%@ for service=%@",
          log: self.log,
          peripheral.identifier.description,
          peripheral.name ?? "",
          characteristic.value?.count ?? 0,
          characteristic.description,
          characteristic.service.description
        )
      }
    }
    
    do {
      self.peripheralsToReadConfigurationsFrom.remove(peripheral)
      guard error == nil else {
        self.cancelConnectionIfNeeded(for: peripheral)
        return
      }
      guard let value = characteristic.value,
        let configuration = try Configuration.init(pdu: value) else {
          throw CBATTError(.invalidPdu)
      }
      let remoteService = try BerkananBluetoothService(
        isLocal: false,
        configuration: configuration
      )
      remoteService.peripheral = peripheral
      var services = self.servicesOfPeripherals[peripheral] ?? Set()
      services.insert(remoteService)
      self.servicesOfPeripherals[peripheral] = services
      services.forEach { $0.rssi = self.rssiOfPeripherals[peripheral] ?? nil }
      #if canImport(Combine)
      if #available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
        self.service?.discoverServiceSubject.send(remoteService)
      }
      #endif
      if let service = self.service {
        service.delegate?.berkananBluetoothService(
          service, didDiscover: remoteService
        )
      }
    }
    catch {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Processing value failed=%@",
          log: self.log,
          type:.error,
          error as CVarArg
        )
      }
    }
  }
  
  func peripheral(
    _ peripheral: CBPeripheral,
    didModifyServices invalidatedServices: [CBService]
  ) {
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Peripheral (uuid=%@ name='%@') did modify services=%@",
        log: self.log,
        peripheral.identifier.description,
        peripheral.name ?? "", invalidatedServices
      )
    }
  }
}

extension BluetoothController: CBPeripheralManagerDelegate {
  
  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    willRestoreState dict: [String : Any]
  ) {
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Peripheral manager will restore state",
        log: self.log
      )
    }
  }
  
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Peripheral manager did update state=%@",
        log: self.log,
        String(describing: peripheral.state.rawValue)
      )
    }
    self._peripheralManagerDidUpdateState(peripheral)
  }
  
  func _peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if #available(OSX 10.15, macCatalyst 13.1, iOS 13.1, tvOS 13.0, watchOS 6.0, *) {
      self.service?.bluetoothAuthorization =
        BluetoothAuthorization(
          cbManagerAuthorization: CBManager.authorization
        ) ?? .notDetermined
    }
    else if #available(OSX 10.15, macCatalyst 13.0, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
      self.service?.bluetoothAuthorization =
        BluetoothAuthorization(
          cbManagerAuthorization: peripheral.authorization
        ) ?? .notDetermined
    }
    else if #available(OSX 10.13, iOS 9.0, *) {
      self.service?.bluetoothAuthorization =
        BluetoothAuthorization(
          cbPeripheralManagerAuthorizationStatus:
          CBPeripheralManager.authorizationStatus()
        ) ?? .notDetermined
    }
    self.stopPeripheralManager()
    switch peripheral.state {
      case .poweredOn:
        let service = BluetoothService.peripheralService
        service.characteristics = [
          BluetoothService.messageCharacteristic,
          BluetoothService.configurationCharacteristic(
            value: try! self.configuration.pdu()
          )
        ]
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
          os_log(
            "Peripheral manager adding service=%@",
            log: self.log,
            service.description
          )
        }
        peripheral.add(service)
      default:
        ()
    }
  }
  
  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didAdd service: CBService,
    error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral manager did add service=%@ error=%@",
          log: self.log,
          type:.error,
          service.description,
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral manager did add service=%@",
          log: self.log,
          service.description
        )
      }
      self.startAdvertising()
    }
  }
  
  private func startAdvertising() {
    self.peripheralManager?.startAdvertising(
      [CBAdvertisementDataServiceUUIDsKey :
        [CBUUID(string: BluetoothService.UUIDPeripheralServiceString)]]
    )
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Peripheral manager starting advertising",
        log: self.log
      )
    }
  }
  
  func peripheralManagerDidStartAdvertising(
    _ peripheral: CBPeripheralManager,
    error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral manager did start advertising error=%@",
          log: self.log,
          type:.error,
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral manager did start advertising",
          log: self.log
        )
      }
    }
  }
  
  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
      os_log(
        "Peripheral manager did receive write requests=%@",
        log: self.log,
        requests.description
      )
    }
    var receivedMessages = [Message]()
    for request in requests {
      do {
        guard request.characteristic.uuid ==
          CBUUID(string: BluetoothService.UUIDMessageCharacteristicString) else {
            throw CBATTError(.requestNotSupported)
        }
        guard let value = request.value,
          let message = try Message.init(pdu: value),
          message.isValid() else {
            throw CBATTError(.invalidPdu)
        }
        receivedMessages.append(message)
        if let peripheral = self.discoveredPeripherals.filter({
          $0.identifier == request.central.identifier
        }).first {
          if message.payloadType == .updatedConfiguration {
            if let services = self.servicesOfPeripherals[peripheral] {
              self.service?.servicesInRange.subtract(services)
            }
            self.servicesOfPeripherals[peripheral]?.forEach {
              $0.rssi = nil
            }
            self.rssiOfPeripherals[peripheral] = nil
            self.servicesOfPeripherals.removeValue(forKey: peripheral)
            // Drastic, but works
            self.discoveredPeripherals.remove(peripheral)
            self.cancelConnectionIfNeeded(for: peripheral)
          }
          else {
            // We received a request from a peripheral that we don't know.
            // Update its configuration.
            if self.servicesOfPeripherals[peripheral]?.isEmpty ?? true {
              self.peripheralsToReadConfigurationsFrom.insert(peripheral)
            }
          }
        }
      }
      catch {
        var result = CBATTError.invalidPdu
        if let error = error as? CBATTError {
          result = error.code
        }
        peripheral.respond(to: request, withResult: result)
        if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
          os_log(
            "Peripheral manager did respond to request=%@ with result=%d",
            log: self.log,
            request.description,
            result.rawValue
          )
        }
        return
      }
    }
    if let request = requests.first {
      peripheral.respond(to: request, withResult: .success)
      if #available(OSX 10.12, iOS 10.0, tvOS 10.0, watchOS 3.0, *) {
        os_log(
          "Peripheral manager did respond to request=%@ with result=%d",
          log: self.log,
          request.description,
          CBATTError.success.rawValue
        )
      }
    }
    // We received a bunch of messages. Resend them to nearby devices,
    // including the source. This way the other apps running on the source are
    // notified of the message too.
    receivedMessages.forEach {
      guard let messageUUID = $0.identifier.foundationValue() else {
        return
      }
      if !self.seenMessageUUIDs.contains(messageUUID) {
        self.addToSeenMessageUUIDsIfNeeded(uuid: messageUUID)
        #if canImport(Combine)
        if #available(OSX 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *) {
          self.service?.receiveMessageSubject.send($0)
        }
        #endif
        if let service = self.service {
          service.delegate?.berkananBluetoothService(service, didReceive: $0)
        }
        // Reduce the number of messages by decreasing the time to live field.
        if $0.timeToLive > 0 {
          var messageCopy = $0
          messageCopy.timeToLive -= 1
          self._send(messageCopy)
        }
      }
    }
  }
}
