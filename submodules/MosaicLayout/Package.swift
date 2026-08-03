// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MosaicLayout",
    platforms: [.iOS(.v15), .macOS(.v11)],
    products: [
        .library(name: "MosaicLayout", targets: ["MosaicLayout"]),
    ],
    targets: [
        .target(name: "MosaicLayout", path: "Sources"),
    ]
)
