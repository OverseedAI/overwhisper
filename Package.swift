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
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/soffes/HotKey.git", from: "0.2.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.5.0")
    ],
    targets: [
        .executableTarget(
            name: "Overwhisper",
            dependencies: [
                "WhisperKit",
                "HotKey",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Overwhisper",
            exclude: [
                "Info.plist",
                "Overwhisper.entitlements"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
