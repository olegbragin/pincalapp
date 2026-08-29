// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SingleCalendarFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "SingleCalendarFeature",
            targets: [
                "SingleCalendarFeature"
            ]
        )
    ],
    dependencies: [
        .package(
            path: "../CorePersistence"
        ),
        .package(
            path: "../DSKit"
        ),
        .package(
            path: "../CoreDomain"
        ),
        .package(
            path: "../AppNavigation"
        )
    ],
    targets: [
        .target(
            name: "SingleCalendarFeature",
            dependencies: [
                "CorePersistence",
                "DSKit",
                "CoreDomain",
                "AppNavigation"
            ],
            path: "Sources/SingleCalendarFeature",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "SingleCalendarFeatureTests",
            dependencies: ["SingleCalendarFeature"],
            path: "Tests/SingleCalendarFeatureTests"
        )
    ]
)
