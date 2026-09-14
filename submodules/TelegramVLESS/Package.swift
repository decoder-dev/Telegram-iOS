// swift-tools-version:5.5

import PackageDescription

let package = Package(
    name: "TelegramVLESS",
    platforms: [.macOS(.v10_15), .iOS(.v13)],
    products: [
        .library(
            name: "TelegramVLESS",
            targets: ["TelegramVLESS"]),
    ],
    dependencies: [
        // The libxray binary target is provided by the build pipeline: CI
        // downloads LibXray.xcframework (XTLS/libxray, checksum-pinned) into
        // third-party/libxray/ before invoking Bazel. It is intentionally not
        // declared here so that the package also compiles without the binary;
        // the runtime adapter is guarded by `#if canImport(LibXray)`.
    ],
    targets: [
        .target(
            name: "TelegramVLESS",
            dependencies: []),
    ]
)
