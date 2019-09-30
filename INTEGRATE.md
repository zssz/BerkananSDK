# Integrate

Currently, BerkananSDK is limited to iOS. Android is planned and is coming soon.

## iOS

To integrate BerkananSDK into your iOS app, use Xcode 11 or later. Open the .xcodeproj or .xcworkspace file of your app and follow these steps.

### Configuring your app target

Select your app target and then go to `Editor` / `Add Capability` / `Background Modes`. Check both `Uses Bluetooth LE accessories` and `Acts as a Bluetooth LE accessory`.

Check the `Bluetooth` checkbox in the `App Sandbox` section in `Signing & Capabilities`.

Add `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription` to the Info.plist with the value:

> Allow access to the Berkanan Bluetooth Network — a public domain messaging service for crowds.

### Adding BerkananSDK to your app

Go to `File` / `Swift Packages` / `Add Package Dependency...` and enter `https://github.com/zssz/BerkananSDK.git`

Add `@import BerkananSDK` to your source files where needed.

### Using BerkananSDK in your app

#### Starting the service

```swift
BerkananNetwork.shared.start()
```

#### Sending messages

```swift
let message = PublicBroadcastMessage(text: "Hello, World!")
BerkananNetwork.shared.broadcast(message)
```

#### Receiving messages...

##### ...via Combine API

```swift
BerkananNetwork.shared.publicBroadcastMessageSubject
      .receive(on: RunLoop.main)
      .receive(subscriber: Subscribers.Sink(
        receiveCompletion: { _ in () },
        receiveValue: { message in
          print("Did receive: ", message)
      }))
```

##### ...via delegate callback

```swift
BerkananNetwork.shared.delegate = ...
```

```swift
func didReceive(_ message: PublicBroadcastMessage) {
  DispatchQueue.main.async {
    print("Did receive: ", message)
  }
}
```

#### Stopping the service

```swift
BerkananNetwork.shared.stop()
```

### Sample app

To see how BerkananSDK is integrated and used in [Berkanan Lite](https://apps.apple.com/us/app/berkanan-messenger-lite/id1479731429), check out its [source code](https://github.com/zssz/BerkananLite).
