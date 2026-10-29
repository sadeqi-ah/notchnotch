// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchNotch", targets: ["NotchNotch"]),
        .executable(name: "ExtensionRunner", targets: ["ExtensionRunner"]),
    ],
    targets: [
        .target(name: "NotchProtocol", path: "native/NotchProtocol/Sources"),
        .target(name: "NotchCore", dependencies: ["NotchProtocol"], path: "native/NotchCore/Sources"),
        .target(name: "NotchRuntime", dependencies: ["NotchProtocol"], path: "native/NotchRuntime/Sources"),
        .target(name: "NotchRenderer", dependencies: ["NotchProtocol", "NotchCore"], path: "native/NotchRenderer/Sources"),
        .executableTarget(name: "ExtensionRunner", dependencies: ["NotchRuntime"], path: "native/ExtensionRunner/Sources"),
        .executableTarget(name: "NotchNotch", dependencies: ["NotchCore", "NotchRenderer"], path: "apps/macos/Sources"),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"], path: "native/NotchCore/Tests"),
        .testTarget(name: "NotchRuntimeTests", dependencies: ["NotchRuntime"], path: "native/NotchRuntime/Tests"),
    ],
    swiftLanguageModes: [.v6]
)
