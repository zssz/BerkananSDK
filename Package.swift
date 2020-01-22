// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to
// build this package.

import PackageDescription

let package = Package(
  name: "BerkananSDK",
  platforms: [
    .iOS(.v9), .macOS(.v10_13), .watchOS(.v2), .tvOS(.v9)
  ],
  products: [
    .library(
      name: "BerkananSDK",
      targets: ["BerkananSDK"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.7.0"),
    .package(url: "https://github.com/zssz/BerkananFoundation", from: "1.0.0"),
    .package(url: "https://github.com/zssz/BerkananCompression", from: "1.0.0")
  ],
  targets: [
    .target(
      name: "CBerkananSDK"),
    .target(
      name: "BerkananSDK",
      dependencies: [
        "CBerkananSDK",
        "SwiftProtobuf",
        "BerkananFoundation",
        "BerkananCompression"
    ]),
    .testTarget(
      name: "BerkananSDKTests",
      dependencies: ["BerkananSDK"]),
  ]
)
