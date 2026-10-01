// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeRemainder",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ClaudeRemainderCore",
            targets: ["ClaudeRemainderCore"]
        ),
        .executable(
            name: "ClaudeRemainder",
            targets: ["ClaudeRemainder"]
        )
    ],
    targets: [
        .target(
            name: "ClaudeRemainderCore"
        ),
        .executableTarget(
            name: "ClaudeRemainder",
            dependencies: ["ClaudeRemainderCore"],
            path: "Sources/ClaudeRemainder",
            sources: [
                "main.swift",
                "AppController.swift",
                "DashboardWindowController.swift",
                "SettingsWindowController.swift",
                "ResourceWindowController.swift"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ClaudeRemainderCoreTests",
            dependencies: ["ClaudeRemainderCore"]
        )
    ]
)
