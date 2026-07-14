// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NovelAgentModules",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "NovelAgentCore", targets: ["NovelAgentCore"]),
        .library(name: "NovelAgentProviders", targets: ["NovelAgentProviders"])
    ],
    targets: [
        .target(
            name: "NovelAgentCore",
            path: "Sources/NovelAgentCore"
        ),
        .target(
            name: "NovelAgentProviders",
            dependencies: ["NovelAgentCore"],
            path: "Sources/NovelAgentProviders"
        ),
        .testTarget(
            name: "NovelAgentCoreTests",
            dependencies: ["NovelAgentCore", "NovelAgentProviders"],
            path: "Tests/NovelAgentCoreTests"
        )
    ]
)

