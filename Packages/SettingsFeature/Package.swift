// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SettingsFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "SettingsFeature",
            targets: ["SettingsFeature"]
        )
    ],
    dependencies: [
        .package(
            path: "../DSKit"
        )
    ],
    targets: [
        .target(
            name: "SettingsFeature",
            dependencies: ["DSKit"],
            path: "Sources/SettingsFeature"
        ),
        .testTarget(
            name: "SettingsFeatureTests",
            dependencies: ["SettingsFeature", "DSKit"],
            path: "Tests/SettingsFeatureTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
