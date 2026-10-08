// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarListFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "CalendarListFeature",
            targets: ["CalendarListFeature"]
        ),
    ],
    dependencies: [
        .package(path: "../CoreDomain"),
        .package(path: "../DSKit"),
        .package(path: "../AppNavigation"),
    ],
    targets: [
        .target(
            name: "CalendarListFeature",
            dependencies: [
                "CoreDomain",
                "DSKit",
                "AppNavigation",
            ],
            path: "Sources/CalendarListFeature",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CalendarListFeatureTests",
            dependencies: ["CalendarListFeature",
                           "CoreDomain"],
            path: "Tests/CalendarListFeatureTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
