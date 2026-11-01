// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MTWebSocketTransport",
    products: [.library(name: "MTWebSocketTransport", targets: ["MTWebSocketTransport"])],
    targets: [
        .target(name: "MTWebSocketTransport", path: "Sources"),
        .testTarget(name: "MTWebSocketTransportTests", dependencies: ["MTWebSocketTransport"], path: "Tests")
    ]
)
