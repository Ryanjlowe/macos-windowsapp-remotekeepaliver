// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "RemoteKeepAliver",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RemoteKeepAliver", targets: ["RemoteKeepAliver"]),
    ],
    targets: [
        .target(name: "KeepAliveCore"),
        .executableTarget(name: "RemoteKeepAliver", dependencies: ["KeepAliveCore"]),
        .testTarget(name: "KeepAliveCoreTests", dependencies: ["KeepAliveCore"]),
    ],
    swiftLanguageModes: [.v5]
)
