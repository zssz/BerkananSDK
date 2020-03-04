# Berkanan SDK [![Tweet](https://img.shields.io/twitter/url/http/shields.io.svg?style=social)](https://twitter.com/intent/tweet?text=Integrate%20Berkanan%20SDK%20into%20your%20app%20and%20help%20create%20a%20decentralized%20mesh%20messaging%20network%20for%20the%20people%2C%20powered%20by%20their%20device%27s%20Bluetooth%20antenna%3A%20https%3A%2F%2Fgithub.com%2Fzssz%2FBerkananSDK)

![build](https://github.com/zssz/BerkananSDK/workflows/build/badge.svg)
[![Contributions](https://img.shields.io/badge/contributions-welcome-blue)](CONTRIBUTING.md)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-v2.0%20adopted-ff69b4.svg)](CODE_OF_CONDUCT.md)

Berkanan SDK enables Bluetooth mesh messaging between nearby apps. It's the framework used by [Berkanan Messenger](https://apps.apple.com/app/berkanan-messenger/id1289061820) ([Product Hunt](https://www.producthunt.com/posts/berkanan), [TechCrunch](https://techcrunch.com/2018/09/27/berkanan-is-a-bluetooth-powered-group-messaging-app/)) and [Berkanan Messenger Lite](https://apps.apple.com/app/berkanan-messenger-lite/id1479731429) ([GitHub](https://github.com/zssz/BerkananLite)).

With Berkanan SDK, apps can discover nearby apps, which also have the SDK integrated and Bluetooth turned on, and send them small messages. The range for these messages is about 70 meters, but they can reach further because the SDK automatically resends them upon receiving. The more apps use Berkanan SDK, the further the reach of the messages gets.

### Features and Limitations
- Free and open-source: Contributions are welcome!
- Bluetooth-powered: No need for Wi-Fi or cellular connectivity.
- Background: On iOS, it works even while in the background. However, background-running apps can't discover each other — the system enforces this policy.
- Connectionless communication with no pairing, no sessions, and no limit on the number of apps.
- For sending messages, the SDK uses [flooding](https://en.wikipedia.org/wiki/Flooding_(computer_networking)), where duplicates are filtered by tracking their identifiers and decreasing their time to live (TTL) by 1, until they reach 0, as they travel from app to app.
- The message range limit between two devices is about 70 meters.
- The data size limit is 512 bytes.
- No built-in support for encryption, [acknowledgment](https://en.wikipedia.org/wiki/Acknowledgement_(data_networks)), or [store and forward](https://en.wikipedia.org/wiki/Store_and_forward). You have to roll your own if your use case requires it.
- It's *not* a [Bluetooth Mesh Networking](https://www.bluetooth.com/specifications/mesh-specifications) implementation.
- Supported operating systems: iOS 9.0 or later, watchOS 4.0 or later, tvOS 9.0 or later, macOS 10.13 or later.

### Privacy Policy
Berkanan SDK does not send the messages to any central server or company.

## Integrating Berkanan SDK into your app

### iOS

To integrate Berkanan SDK into your iOS app, use Xcode 11 or later. Open the .xcodeproj or .xcworkspace file of your app and follow these steps.

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

##### Stopping the local service

```swift
service.stop()
```

#### Sample app

To see how [Berkanan Messenger Lite app](https://apps.apple.com/app/berkanan-messenger-lite/id1479731429) integrates Berkanan SDK, check out its [source code](https://github.com/zssz/BerkananLite).
