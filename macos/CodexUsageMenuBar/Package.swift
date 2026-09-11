// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexUsageMenuBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "CodexUsageMenuBar", targets: ["CodexUsageMenuBar"]),
        .executable(name: "UsageCoreCheck", targets: ["UsageCoreCheck"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(
            name: "CodexUsageMenuBar",
            dependencies: ["UsageCore"]
        ),
        .executableTarget(
            name: "UsageCoreCheck",
            dependencies: ["UsageCore"]
        ),
    ]
)
