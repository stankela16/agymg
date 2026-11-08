// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "agymg",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "agymg", targets: ["AntigravityManager"])
    ],
    targets: [
        .executableTarget(
            name: "AntigravityManager",
            path: "Sources/AntigravityManager",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "AntigravityManagerTests",
            dependencies: ["AntigravityManager"],
            path: "Tests/AntigravityManagerTests"
        )
    ]
)
