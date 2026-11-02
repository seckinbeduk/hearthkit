// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HearthKit",
    // The third-party model surface of Foundation Models (`LanguageModel`, `LanguageModelExecutor`)
    // arrived with the macOS 27 SDK.
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "HearthKit", targets: ["HearthKit"]),
        .executable(name: "hearthkit-demo", targets: ["hearthkit-demo"]),
    ],
    targets: [
        // No dependencies: Foundation and Foundation Models only.
        .target(name: "HearthKit"),
        .executableTarget(name: "hearthkit-demo", dependencies: ["HearthKit"]),
        .testTarget(name: "HearthKitTests", dependencies: ["HearthKit"]),
    ]
)
