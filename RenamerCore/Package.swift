// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RenamerCore",
    platforms: [.macOS(.v13)],
    products: [
        // The engine: pure logic, no UI. The SwiftUI app (added once Xcode is
        // installed) will depend on this product via a local path.
        .library(name: "RenamerCore", targets: ["RenamerCore"]),
    ],
    targets: [
        .target(name: "RenamerCore"),
        .testTarget(name: "RenamerCoreTests", dependencies: ["RenamerCore"]),
    ]
)
