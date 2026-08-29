// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AppNavigation",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "AppNavigation",
            targets: ["AppNavigation"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AppNavigation",
            dependencies: [],
            path: "Sources/AppNavigation"
        ),
        .testTarget(
            name: "AppNavigationTests",
            dependencies: ["AppNavigation"],
            path: "Tests/AppNavigationTests"
        )
    ]
)
