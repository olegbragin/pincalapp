// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SingleCalendarFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SingleCalendarFeature", targets: ["SingleCalendarFeature"])
    ],
    dependencies: [
        .package(path: "../CorePersistence"),
        .package(path: "../DSKit"),
        .package(path: "../CoreDomain"),
        .package(path: "../AppNavigation"),
        .package(url: "https://github.com/objectbox/objectbox-swift-spm", from: "5.3.0")
    ],
    targets: [
        .target(
            name: "SingleCalendarFeature",
            dependencies: [
                "CorePersistence",
                "DSKit",
                "CoreDomain",
                "AppNavigation",
                .product(name: "ObjectBox.xcframework", package: "objectbox-swift-spm")
            ],
            path: "Sources/SingleCalendarFeature"
        ),
        .testTarget(name: "SingleCalendarFeatureTests", dependencies: ["SingleCalendarFeature"], path: "Tests/SingleCalendarFeatureTests")
    ]
)
