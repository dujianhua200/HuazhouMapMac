// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HuazhouMap",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HuazhouMap", targets: ["HuazhouMap"]),
        .library(name: "HuazhouCore", targets: ["HuazhouCore"]),
    ],
    targets: [
        .target(
            name: "HuazhouCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "HuazhouMap",
            dependencies: ["HuazhouCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HuazhouCoreTests",
            dependencies: ["HuazhouCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
