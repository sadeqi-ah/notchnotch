// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchNotch", targets: ["NotchNotch"]),
        .executable(name: "ExtensionRunner", targets: ["ExtensionRunner"]),
        .executable(name: "MusicAdapter", targets: ["MusicAdapter"]),
        .executable(name: "CalendarAdapter", targets: ["CalendarAdapter"]),
    ],
    targets: [
        .target(name: "NotchProtocol", path: "native/NotchProtocol/Sources"),
        .target(name: "NotchCore", dependencies: ["NotchProtocol"], path: "native/NotchCore/Sources"),
        .target(name: "NotchRuntime", dependencies: ["NotchProtocol"], path: "native/NotchRuntime/Sources"),
        .target(name: "NotchConnections", dependencies: ["NotchProtocol"], path: "native/NotchConnections/Sources"),
        .target(name: "NotchExtensions", dependencies: ["NotchProtocol"], path: "native/NotchExtensions/Sources"),
        .target(name: "NotchRenderer", dependencies: ["NotchProtocol", "NotchCore"], path: "native/NotchRenderer/Sources"),
        .executableTarget(name: "ExtensionRunner", dependencies: ["NotchRuntime"], path: "native/ExtensionRunner/Sources"),
        .executableTarget(name: "MusicAdapter", dependencies: ["NotchCore", "NotchProtocol"], path: "extensions/music/helper-src"),
        .target(name: "CalendarSupport", path: "extensions/calendar/helper-core"),
        .executableTarget(name: "CalendarAdapter", dependencies: ["CalendarSupport", "NotchProtocol"], path: "extensions/calendar/helper-src"),
        .testTarget(name: "CalendarSupportTests", dependencies: ["CalendarSupport"], path: "extensions/calendar/helper-tests"),
        .executableTarget(name: "NotchNotch", dependencies: ["NotchCore", "NotchRenderer", "NotchConnections", "NotchExtensions"], path: "apps/macos/Sources"),
        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"], path: "native/NotchCore/Tests"),
        .testTarget(name: "NotchRuntimeTests", dependencies: ["NotchRuntime"], path: "native/NotchRuntime/Tests"),
        .testTarget(name: "NotchConnectionsTests", dependencies: ["NotchConnections"], path: "native/NotchConnections/Tests"),
        .testTarget(name: "NotchExtensionsTests", dependencies: ["NotchExtensions"], path: "native/NotchExtensions/Tests"),
    ],
    swiftLanguageModes: [.v6]
)
