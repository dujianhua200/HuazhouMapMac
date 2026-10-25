// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HuazhouMap",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HuazhouMap", targets: ["HuazhouMap"]),
        .library(name: "HuazhouCore", targets: ["HuazhouCore"]),
        .library(name: "HuazhouAppCore", targets: ["HuazhouAppCore"]),
    ],
    targets: [
        .target(
            name: "HuazhouCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 应用状态机与文件/导出逻辑（可单测，不含 SwiftUI 视图）
        .target(
            name: "HuazhouAppCore",
            dependencies: ["HuazhouCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "HuazhouMap",
            dependencies: ["HuazhouCore", "HuazhouAppCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HuazhouCoreTests",
            dependencies: ["HuazhouCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HuazhouAppCoreTests",
            dependencies: ["HuazhouAppCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
