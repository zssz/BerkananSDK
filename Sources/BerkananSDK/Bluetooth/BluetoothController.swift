//
// Copyright © 2019 IZE Ltd. and the project authors
// Licensed under MIT License
//
// See LICENSE.txt for license information.
//

import Foundation
import CoreBluetooth
#if canImport(UIKit)
import UIKit.UIApplication
#endif
import os.log

/// The controller responsible for the Bluetooth communication.
class BluetoothController: NSObject {
  
  static let shared = BluetoothController()
  
  @available(OSX 10.12, iOS 10.0, *)
  private static let log = OSLog(
    subsystem: "chat.berkanan.sdk",
    category: "BerkananSDK"
  )
  
  private let dispatchQueue = DispatchQueue(
    label: "chat.berkanan.sdk." + Bundle.main.bundleIdentifier!,
    qos: .userInteractive
  )
  
  private var centralManager: CBCentralManager?
  
  private var discoveredPeripherals = Set<CBPeripheral>()
  
  private static let peripheralDiscoveryTimeout: TimeInterval = 12
  
  private var timeoutTimersForPeripheralIdentifiers = [UUID : Timer]()
  
  private var connectedPeripherals = Set<CBPeripheral>()
  
  private var connectionStateObservationsForPeripheralIdentifiers =
    [UUID : NSKeyValueObservation]()
  
  private static let maxNumberOfConcurrentPeripheralConnections = 5
  
  private var messagesForPeripherals =
    [CBPeripheral : [PublicBroadcastMessage]]()
  
  private static let transferTimeout: TimeInterval = 3
  
  private var seenMessageUUIDs =
    NSMutableOrderedSet(capacity: seenMessageUUIDsCacheLimit)
  
  private static let seenMessageUUIDsCacheLimit = 1024
  
  private var peripheralManager: CBPeripheralManager?
  
  override init() {
    super.init()
    #if canImport(UIKit)
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
    #if canImport(UIKit)
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
      guard let self = self else {
        return
      }
      self.timeoutTimersForPeripheralIdentifiers.values.forEach {
        $0.invalidate()
      }
      self.timeoutTimersForPeripheralIdentifiers.removeAll()
    }
  }
  
  @objc func applicationWillEnterForegroundNotification(
    _ notification: Notification
  ) {
    self.dispatchQueue.async { [weak self] in
      guard let self = self else {
        return
      }
      self.discoveredPeripherals.forEach {
        self.setupTimeoutTimer(for: $0)
      }
    }
  }
  
  // MARK: - Public
  
  /// Returns true if the service is started.
  public var isStarted: Bool {
    return self.centralManager != nil
  }
  
  /// Starts the service.
  public func start() {
    self.dispatchQueue.async { [weak self] in
      guard let self = self else {
        return
      }
      guard self.centralManager == nil else {
        return
      }
      self.centralManager = CBCentralManager(
        delegate: self,
        queue: self.dispatchQueue,
        options: nil
      )
      self.peripheralManager = CBPeripheralManager(
        delegate: self,
        queue: self.dispatchQueue,
        options: [
          CBPeripheralManagerOptionRestoreIdentifierKey:
            "chat.berkanan.sdk.peripheral." + Bundle.main.bundleIdentifier!
        ]
      )
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log("Started", log: BluetoothController.log)
      }
    }
  }
  
  /// Stops the service.
  public func stop() {
    self.dispatchQueue.async { [weak self] in
      guard let self = self else {
        return
      }
      self.timeoutTimersForPeripheralIdentifiers.values.forEach {
        $0.invalidate()
      }
      self.timeoutTimersForPeripheralIdentifiers.removeAll()
      self.discoveredPeripherals.forEach {
        $0.delegate = nil
        self.cancelConnectionIfNeeded(for: $0)
      }
      self.discoveredPeripherals.removeAll()
      BerkananNetwork.shared.numberOfNearbyUsers =
        self.discoveredPeripherals.count
      self.connectedPeripherals.removeAll()
      self.connectionStateObservationsForPeripheralIdentifiers.removeAll()
      self.messagesForPeripherals.removeAll()
      self.seenMessageUUIDs.removeAllObjects()
      if self.centralManager?.isScanning ?? false {
        self.centralManager?.stopScan()
      }
      self.centralManager?.delegate = nil
      self.centralManager = nil
      if self.peripheralManager?.isAdvertising ?? false {
        self.peripheralManager?.stopAdvertising()
      }
      self.peripheralManager?.removeAllServices()
      self.peripheralManager?.delegate = nil
      self.peripheralManager = nil
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log("Stopped", log: BluetoothController.log)
      }
    }
  }
  
  /// Enqueues `message` to send to nearby devices.
  /// - Parameter message: The message to be sent.
  public func send(_ message: PublicBroadcastMessage) {
    self.dispatchQueue.async { [weak self] in
      guard let self = self else {
        return
      }
      guard self.discoveredPeripherals.count > 0 else {
        return
      }
      guard let messageUUID = message.uuid else {
        return
      }
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Enqueued message (uuid=%@ payload='%@')",
          log: BluetoothController.log,
          messageUUID.description,
          message.text ?? ""
        )
      }
      self.addToSeenMessageUUIDsIfNeeded(uuid: messageUUID)
      self.discoveredPeripherals.forEach {
        self.enqueue(message: message, for: $0)
      }
      self.connectPeripheralsIfNeeded()
    }
  }
  
  // MARK: - Private
  
  private func enqueue(
    message: PublicBroadcastMessage,
    for peripheral: CBPeripheral
  ) {
    if self.messagesForPeripherals[peripheral] == nil {
      self.messagesForPeripherals[peripheral] = [PublicBroadcastMessage]()
    }
    var messages = self.messagesForPeripherals[peripheral]
    messages?.append(message)
    self.messagesForPeripherals[peripheral] = messages
  }
  
  private func connectPeripheralsIfNeeded() {
    guard messagesForPeripherals.count > 0 else {
      return
    }
    guard connectedPeripherals.count <
      BluetoothController.maxNumberOfConcurrentPeripheralConnections else {
        return
    }
    let disconnectedPeripherals = messagesForPeripherals.keys.filter {
      $0.state == .disconnected || $0.state == .disconnecting
    }
    disconnectedPeripherals.prefix(
      BluetoothController.maxNumberOfConcurrentPeripheralConnections -
        connectedPeripherals.count
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
        if #available(OSX 10.12, iOS 10.0, *) {
          os_log(
            "Central manager connecting peripheral (uuid=%@ name='%@')",
            log: BluetoothController.log,
            peripheral.identifier.description,
            peripheral.name ?? ""
          )
        }
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
  
  private func setupTimeoutTimer(for peripheral: CBPeripheral) {
    let timer = Timer.init(
      timeInterval: BluetoothController.peripheralDiscoveryTimeout,
      target: self,
      selector: #selector(_timeoutTimerFired(timer:)),
      userInfo: ["peripheral" : peripheral],
      repeats: true
    )
    timer.tolerance = 0.5
    RunLoop.main.add(timer, forMode: .common)
    timeoutTimersForPeripheralIdentifiers[peripheral.identifier]?.invalidate()
    timeoutTimersForPeripheralIdentifiers[peripheral.identifier] = timer
  }
  
  @objc private func _timeoutTimerFired(timer: Timer) {
    self.dispatchQueue.async { [weak self] in
      defer {
        timer.invalidate()
      }
      guard let self = self else {
        return
      }
      guard let userInfo = timer.userInfo as? [AnyHashable : Any],
        let peripheral = userInfo["peripheral"] as? CBPeripheral else {
          return
      }
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Did time out peripheral (uuid=%@ name='%@')",
          log: BluetoothController.log,
          peripheral.identifier.description,
          peripheral.name ?? ""
        )
      }
      peripheral.delegate = nil
      self.cancelConnectionIfNeeded(for: peripheral)
      self.discoveredPeripherals.remove(peripheral)
      BerkananNetwork.shared.numberOfNearbyUsers =
        self.discoveredPeripherals.count
      self.connectedPeripherals.remove(peripheral)
      self.connectionStateObservationsForPeripheralIdentifiers[
        peripheral.identifier
        ] = nil
      self.timeoutTimersForPeripheralIdentifiers[peripheral.identifier] = nil
      self.messagesForPeripherals.removeValue(forKey: peripheral)
    }
  }
  
  private func cancelConnectionIfNeeded(for peripheral: CBPeripheral) {
    guard peripheral.state != .disconnected else {
      return
    }
    centralManager?.cancelPeripheralConnection(peripheral)
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Central manager cancelled peripheral (uuid=%@ name='%@') connection",
        log: BluetoothController.log,
        peripheral.identifier.description,
        peripheral.name ?? ""
      )
    }
  }
}

extension BluetoothController: CBCentralManagerDelegate {
  
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Central manager did update state=%@",
        log: BluetoothController.log,
        String(describing: central.state.rawValue)
      )
    }
    switch central.state {
      case .poweredOn:
        if central.isScanning {
          central.stopScan()
        }
        let services = [
          CBUUID(string: BerkananService.UUIDPeripheralServiceString)
        ]
        central.scanForPeripherals(
          withServices: services,
          options: [CBCentralManagerScanOptionAllowDuplicatesKey :
            NSNumber(booleanLiteral: true)]
        )
        if #available(OSX 10.12, iOS 10.0, *) {
          os_log(
            "Central manager scanning for peripherals with services=%@",
            log: BluetoothController.log,
            services
          )
      }
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
    if !discoveredPeripherals.contains(peripheral) {
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Central manager did discover new peripheral (uuid=%@ name='%@') RSSI=%d",
          log: BluetoothController.log,
          peripheral.identifier.description,
          peripheral.name ?? "",
          RSSI.intValue
        )
      }
      connectionStateObservationsForPeripheralIdentifiers[
        peripheral.identifier
        ] = peripheral.observe(\.state) { [weak self] (peripheral, _) in
          if peripheral.state == .disconnected {
            self?.connectedPeripherals.remove(peripheral)
            self?.messagesForPeripherals.removeValue(forKey: peripheral)
            self?.connectPeripheralsIfNeeded()
          }
          else {
            self?.connectedPeripherals.insert(peripheral)
          }
      }
    }
    discoveredPeripherals.insert(peripheral)
    BerkananNetwork.shared.numberOfNearbyUsers =
      self.discoveredPeripherals.count
    #if canImport(UIKit)
    DispatchQueue.main.async { [weak self] in
      guard UIApplication.shared.applicationState != .background else {
        return
      }
      self?.setupTimeoutTimer(for: peripheral)
    }
    #else
    setupTimeoutTimer(for: peripheral)
    #endif
  }
  
  func centralManager(
    _ central: CBCentralManager,
    didConnect peripheral: CBPeripheral
  ) {
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Central manager did connect peripheral (uuid=%@ name='%@')",
        log: BluetoothController.log,
        peripheral.identifier.description,
        peripheral.name ?? ""
      )
    }
    self._centralManager(central, didConnect: peripheral)
  }
  
  func _centralManager(
    _ central: CBCentralManager,
    didConnect peripheral: CBPeripheral
  ) {
    peripheral.delegate = self
    if peripheral.services == nil {
      let services = [
        CBUUID(string: BerkananService.UUIDPeripheralServiceString)
      ]
      peripheral.discoverServices(services)
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') discovering services=%@",
          log: BluetoothController.log,
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
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Central manager did fail to connect peripheral (uuid=%@ name='%@') error=%@",
        log: BluetoothController.log,
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
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Central manager did disconnect peripheral (uuid=%@ name='%@') error=%@",
          log: BluetoothController.log,
          type:.error,
          peripheral.identifier.description,
          peripheral.name ?? "",
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Central manager did disconnect peripheral (uuid=%@ name='%@')",
          log: BluetoothController.log,
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
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did discover services error=%@",
          log: BluetoothController.log,
          type:.error,
          peripheral.identifier.description,
          peripheral.name ?? "",
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did discover services",
          log: BluetoothController.log,
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
        let characteristics = [CBUUID(
          string: BerkananService.UUIDPublicBroadcastMessageCharacteristicString
          )]
        peripheral.discoverCharacteristics(characteristics, for: service)
        if #available(OSX 10.12, iOS 10.0, *) {
          os_log(
            "Peripheral (uuid=%@ name='%@') discovering characteristics=%@ for service=%@",
            log: BluetoothController.log,
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
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did discover characteristics for service=%@ error=%@",
          log: BluetoothController.log,
          type:.error,
          peripheral.identifier.description,
          peripheral.name ?? "",
          service.description,
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did discover characteristics for service=%@",
          log: BluetoothController.log,
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
    self.dispatchQueue.asyncAfter(
      deadline: DispatchTime.now() + BluetoothController.transferTimeout
    ) { [weak self] in
      guard let self = self else {
        return
      }
      guard let messages = self.messagesForPeripherals[peripheral],
        messages.count > 0  else {
          self.cancelConnectionIfNeeded(for: peripheral)
          return
      }
      self._peripheral(peripheral, didDiscoverServices: nil)
    }
    self.messagesForPeripherals.removeValue(forKey: peripheral)
  }
  
  func _peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard error == nil,
      let characteristic = service.characteristics?.first,
      let messages = messagesForPeripherals[peripheral],
      messages.count > 0 else {
        self.cancelConnectionIfNeeded(for: peripheral)
        return
    }
    do {
      for message in messages {
        var data: Data
        // To reduce the number of messages in the network set time to live to 0
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
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        if #available(OSX 10.12, iOS 10.0, *) {
          os_log(
            "Peripheral (uuid=%@ name='%@') writing value=%{iec-bytes}d for characteristic=%@ for service=%@",
            log: BluetoothController.log,
            peripheral.identifier.description,
            peripheral.name ?? "",
            data.count,
            characteristic.description,
            service.description
          )
        }
      }
    }
    catch {
      self.cancelConnectionIfNeeded(for: peripheral)
    }
  }
  
  func peripheral(
    _ peripheral: CBPeripheral,
    didWriteValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did write value for characteristic=%@ for service=%@ error=%@",
          log: BluetoothController.log,
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
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral (uuid=%@ name='%@') did write value for characteristic=%@ for service=%@",
          log: BluetoothController.log,
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
    didModifyServices invalidatedServices: [CBService]
  ) {
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Peripheral (uuid=%@ name='%@') did modify services=%@",
        log: BluetoothController.log,
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
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Peripheral manager will restore state",
        log: BluetoothController.log
      )
    }
  }
  
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Peripheral manager did update state=%@",
        log: BluetoothController.log,
        String(describing: peripheral.state.rawValue)
      )
    }
    if #available(OSX 10.15, iOS 13.0, *) {
      BerkananNetwork.shared.bluetoothAuthorization =
        BluetoothAuthorization(
          cbManagerAuthorization: peripheral.authorization
        ) ?? .notDetermined
    }
    else if #available(OSX 10.13, *) {
      BerkananNetwork.shared.bluetoothAuthorization =
        BluetoothAuthorization(
          cbPeripheralManagerAuthorizationStatus:
          CBPeripheralManager.authorizationStatus()
        ) ?? .notDetermined
    }
    switch peripheral.state {
      case .poweredOn:
        if peripheral.isAdvertising {
          peripheral.stopAdvertising()
        }
        peripheral.removeAllServices()
        let service = BerkananService.peripheralService
        if #available(OSX 10.12, iOS 10.0, *) {
          os_log(
            "Peripheral manager adding service=%@",
            log: BluetoothController.log,
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
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral manager did add service=%@ error=%@",
          log: BluetoothController.log,
          type:.error,
          service.description,
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral manager did add service=%@",
          log: BluetoothController.log,
          service.description
        )
      }
      self.startAdvertising()
    }
  }
  
  private func startAdvertising() {
    self.peripheralManager?.startAdvertising(
      [CBAdvertisementDataServiceUUIDsKey :
        [CBUUID(string: BerkananService.UUIDPeripheralServiceString)]]
    )
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Peripheral manager starting advertising",
        log: BluetoothController.log
      )
    }
  }
  
  func peripheralManagerDidStartAdvertising(
    _ peripheral: CBPeripheralManager,
    error: Error?
  ) {
    if let error = error {
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral manager did start advertising error=%@",
          log: BluetoothController.log,
          type:.error,
          error as CVarArg
        )
      }
    }
    else {
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral manager did start advertising",
          log: BluetoothController.log
        )
      }
    }
  }
  
  func peripheralManager(
    _ peripheral: CBPeripheralManager,
    didReceiveWrite requests: [CBATTRequest]
  ) {
    if #available(OSX 10.12, iOS 10.0, *) {
      os_log(
        "Peripheral manager did receive write requests=%@",
        log: BluetoothController.log,
        requests.description
      )
    }
    var receivedMessages = [PublicBroadcastMessage]()
    for request in requests {
      do {
        guard request.characteristic.uuid ==
          BerkananService.publicBroadcastMessageCharacteristic.uuid else {
            throw CBATTError(.requestNotSupported)
        }
        guard let value = request.value,
          let message = try PublicBroadcastMessage.init(pdu: value),
          // Discard message if it does not have the uuid field set
          let _ = message.uuid else {
            throw CBATTError(.invalidPdu)
        }
        receivedMessages.append(message)
      }
      catch {
        var result = CBATTError.invalidPdu
        if let error = error as? CBATTError {
          result = error.code
        }
        peripheral.respond(to: request, withResult: result)
        if #available(OSX 10.12, iOS 10.0, *) {
          os_log(
            "Peripheral manager did respond to request=%@ with result=%d",
            log: BluetoothController.log,
            request.description,
            result.rawValue
          )
        }
        return
      }
    }
    if let request = requests.first {
      peripheral.respond(to: request, withResult: .success)
      if #available(OSX 10.12, iOS 10.0, *) {
        os_log(
          "Peripheral manager did respond to request=%@ with result=%d",
          log: BluetoothController.log,
          request.description,
          CBATTError.success.rawValue
        )
      }
    }
    // We received a bunch of messages. Resend them to nearby devices,
    // including the source. This way the other apps running on the source are
    // notified of the message too.
    receivedMessages.forEach {
      guard let messageUUID = $0.uuid else {
        return
      }
      if !seenMessageUUIDs.contains(messageUUID) {
        self.addToSeenMessageUUIDsIfNeeded(uuid: messageUUID)
        #if canImport(Combine)
        if #available(OSX 10.15, iOS 13.0, *) {
          BerkananNetwork.shared.publicBroadcastMessageSubject.send($0)
        }
        #endif
        BerkananNetwork.shared.delegate?.didReceive($0)
        // Reduce the number of messages in the network by decreasing the time
        // to live field.
        if $0.timeToLive > 0 {
          var messageCopy = $0
          messageCopy.timeToLive -= 1
          send(messageCopy)
        }
      }
    }
  }
}
