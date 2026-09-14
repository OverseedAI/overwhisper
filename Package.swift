// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Overwhisper",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Overwhisper", targets: ["Overwhisper"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.5.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(url: "https://github.com/PostHog/posthog-ios.git", exact: "3.64.6")
    ],
    targets: [
        .executableTarget(
            name: "Overwhisper",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                "HotKey",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "PostHog", package: "posthog-ios")
            ],
            path: "Overwhisper",
            exclude: [
                "Info.plist",
                "Overwhisper.entitlements"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OverwhisperTests",
            dependencies: ["Overwhisper"],
            path: "Tests/OverwhisperTests"
        )
    ]
)
