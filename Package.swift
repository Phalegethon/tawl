// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tawl", platforms: [.macOS(.v15)],
    products: [.executable(name: "tawl", targets: ["Tawl"])],
    targets: [
        .target(name: "CTawl", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "TawlCore", dependencies: ["CTawl"], linkerSettings: [.linkedFramework("AppKit")]),
        .executableTarget(name: "Tawl", dependencies: ["TawlCore", "CTawl"]),
        .testTarget(name: "TawlCoreTests", dependencies: ["TawlCore"])
    ], swiftLanguageModes: [.v5]
)
