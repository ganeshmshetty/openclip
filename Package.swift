// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenClip",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "OpenClip", targets: ["OpenClip"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sindresorhus/Defaults", from: "8.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "OpenClip",
            dependencies: [
                "KeyboardShortcuts",
                "Defaults",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/OpenClip",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
