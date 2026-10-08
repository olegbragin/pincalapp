// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SingleCalendarFeature",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "SingleCalendarFeature",
            targets: [
                "SingleCalendarFeature",
            ]
        ),
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
        ),
    ],
    targets: [
        .target(
            name: "SingleCalendarFeature",
            // No CorePersistence. Stage 9 removed the last import; the package reaches
            // storage only through the domain ports.
            dependencies: [
                "DSKit",
                "CoreDomain",
                "AppNavigation",
            ],
            path: "Sources/SingleCalendarFeature",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SingleCalendarFeatureTests",
            dependencies: [
                "SingleCalendarFeature",
                "CorePersistence",
                "DSKit",
                "CoreDomain",
                "AppNavigation",
            ],
            path: "Tests/SingleCalendarFeatureTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
