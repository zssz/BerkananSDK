# Berkanan SDK

Berkanan SDK enables Bluetooth-powered mesh messaging between nearby apps. It's the framework used by [Berkanan](https://apps.apple.com/us/app/berkanan-messenger/id1289061820) ([Product Hunt](https://www.producthunt.com/posts/berkanan), [TechCrunch](https://techcrunch.com/2018/09/27/berkanan-is-a-bluetooth-powered-group-messaging-app/)) and [Berkanan Lite](https://apps.apple.com/us/app/berkanan-messenger-lite/id1479731429) ([GitHub](https://github.com/zssz/BerkananLite)).

With Berkanan SDK apps can discover nearby apps, which also have the SDK integrated, and send them small messages via Bluetooth. The range for messages is about 70 meters, but they can reach further because the SDK automatically resends them upon receiving. The more apps use Berkanan SDK, the bigger the network and further the reach of the messages gets.

### Features and Limitations
- Free and open-source: Contributions are welcome!
- Bluetooth-powered: No need for Wi-Fi or cellular connectivity.
- Background: On iOS it works even while the app is in the background.
- Connectionless communication with no pairing, no sessions and no limit on the number of apps.
- Messages are sent using [flooding](https://en.wikipedia.org/wiki/Flooding_(computer_networking)) where duplicates are filtered by tracking their identifiers and decreasing their time to live (TTL) by 1 until they reach 0, as they travel from app to app.
- The message range limit between two devices is about 70 meters.
- The data size limit is 512 bytes.
- No built-in support for encryption, [acknowledgment](https://en.wikipedia.org/wiki/Acknowledgement_(data_networks)) or [store and forward](https://en.wikipedia.org/wiki/Store_and_forward); you have to roll your own if your use case requires it.
- Supported operating systems: iOS v9.0 or later, macOS v10.13 or later, watchOS v2.0 or later, tvOS v9.0 or later

### Privacy Policy
Berkanan SDK does not send the messages to any central server or company — this can be verified by looking at its source code. If your app's messages contain sensitive information (e.g., a private text message) you should use encryption.

## Integrating Berkanan SDK into Your App

### iOS

To integrate Berkanan SDK into your iOS app, the easiest way is to use Xcode 11 or later. Open the .xcodeproj or .xcworkspace file of your app and follow these steps.

#### Configuring your app target

Select your app target and then go to `Editor` / `Add Capability` / `Background Modes`. Check both `Uses Bluetooth LE accessories` and `Acts as a Bluetooth LE accessory`.

Go to `Signing & Capabilities` /  `App Sandbox` and check the `Bluetooth` checkbox. 

Add `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription` to the Info.plist with the value:

> Allow access to the Berkanan Bluetooth Service to be able to communicate even while offline.

#### Adding Berkanan SDK to your app

Go to `File` / `Swift Packages` / `Add Package Dependency...` and enter `https://github.com/zssz/BerkananSDK.git`

Add `@import BerkananSDK` to your source files where needed.

#### Using Berkanan SDK in your app

##### Initializing a local service with a configuration to advertise

```swift
let configuration = Configuration(
  // The identifier is used to identify what kind of configuration the service has. 
  // It should be the same across app runs.
  identifier: UUID(uuidString: "3749ED8E-DBA0-4095-822B-1DC61762CCF3")!, 
  userInfo: "My User Info".data(using: .utf8)!
)
// Throws if the configuration is too big or invalid.
let service = try BerkananBluetoothService(configuration: configuration)
```

##### Starting a local service

```swift
service.start()
```

##### Discovering nearby services and their advertised configuration

```swift
let discoverServiceCanceller = service.discoverServiceSubject
  .receive(on: RunLoop.main)
  .sink { service in
    print("Discovered \(service) with \(service.getConfiguration())")
}
```

##### Constructing a message with a payload type identifier and payload

```swift
let message = Message(
  // The payloadType is used to identify what kind of payload the message carries.
  payloadType: UUID(uuidString: "E268F3C1-5ADB-4412-BE04-F4A04F9B3D1A")!,
  payload: "Hello, World!".data(using: .utf8)
)
```

##### Sending a message

```swift
// Throws if the message is too big or invalid.
try service.send(message)
```

##### Receiving messages

```swift
let receiveMessageCanceller = service.receiveMessageSubject
  .receive(on: RunLoop.main)
  .sink { message in
    print("Received \(message.payloadType) \(message.payload)")
}
```

##### Stopping the service

```swift
service.stop()
```

#### Sample app

To see how Berkanan SDK is integrated into [Berkanan Lite](https://apps.apple.com/us/app/berkanan-messenger-lite/id1479731429), check out its [source code](https://github.com/zssz/BerkananLite).
