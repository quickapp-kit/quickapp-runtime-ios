// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "quickapp-runtime-ios",
  platforms: [
    .iOS(.v15),
    .macOS(.v13),
  ],
  products: [
    .library(name: "QuickAppRuntimeIOSFoundation", targets: ["QuickAppRuntimeIOSFoundation"])
  ],
  targets: [
    .target(name: "QuickAppRuntimeIOSFoundation"),
    .testTarget(
      name: "QuickAppRuntimeIOSFoundationTests",
      dependencies: ["QuickAppRuntimeIOSFoundation"],
      resources: [.process("Fixtures")]
    ),
  ],
  swiftLanguageModes: [.v5]
)
