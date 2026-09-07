// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarListFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "CalendarListFeature",
            targets: ["CalendarListFeature"]
        )
    ],
    dependencies: [
        .package(path: "../CorePersistence"),
        .package(path: "../DSKit"),
        .package(path: "../AppNavigation")
    ],
    targets: [
        .target(
            name: "CalendarListFeature",
            dependencies: [
                "CorePersistence",
                "DSKit",
                "AppNavigation"
            ],
            path: "Sources/CalendarListFeature"
        ),
        .testTarget(
            name: "CalendarListFeatureTests",
            dependencies: [
                "CalendarListFeature",
                "CorePersistence"
            ],
            path: "Tests/CalendarListFeatureTests"
        )
    ],
    swiftLanguageModes: [.v6],
)
