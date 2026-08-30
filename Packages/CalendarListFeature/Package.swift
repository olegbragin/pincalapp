// swift-tools-version: 5.10
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
        .package(path: "../CoreDomain"),
        .package(path: "../AppNavigation")
    ],
    targets: [
        .target(
            name: "CalendarListFeature",
            dependencies: [
                "CorePersistence",
                "DSKit",
                "CoreDomain",
                "AppNavigation"
            ],
            path: "Sources/CalendarListFeature"
        ),
        .testTarget(
            name: "CalendarListFeatureTests",
            dependencies: [
                "CalendarListFeature",
                "CorePersistence",
                "CoreDomain"
            ],
            path: "Tests/CalendarListFeatureTests"
        )
    ]
)
