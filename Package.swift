// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Soonbar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SoonbarCore"),
        .executableTarget(
            name: "Soonbar",
            dependencies: ["SoonbarCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "SoonbarCoreTests", dependencies: ["SoonbarCore"]),
    ]
)
