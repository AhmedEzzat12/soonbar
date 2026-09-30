// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Soonbar",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-updates (appcast + EdDSA-signed zips on GitHub Releases).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "SoonbarCore"),
        .executableTarget(
            name: "Soonbar",
            dependencies: ["SoonbarCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            // Sparkle.framework is embedded in Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "SoonbarCoreTests", dependencies: ["SoonbarCore"]),
        // Renders docs/demo.mp4 (motion graphics driven by SoonbarCore). Not part of the app.
        .executableTarget(
            name: "DemoVideo",
            dependencies: ["SoonbarCore"],
            path: "Tools/DemoVideo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
