// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "EZSwiftData",
  platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26), .watchOS(.v26)],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "EZSwiftData",
      targets: ["EZSwiftData"]
    ),
    .library(
      name: "EZSwiftDataCloudKit",
      targets: ["EZSwiftDataCloudKit"]
    ),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "EZSwiftData",
      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
    ),
    .target(
      name: "EZSwiftDataCloudKit",
      dependencies: ["EZSwiftData"],
      swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
    ),
    .testTarget(
      name: "EZSwiftDataTests",
      dependencies: ["EZSwiftData"]
    ),
    .testTarget(
      name: "EZSwiftDataCloudKitTests",
      dependencies: ["EZSwiftData", "EZSwiftDataCloudKit"]
    ),
  ]
)
