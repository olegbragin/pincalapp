// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DSKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DSKit", targets: ["DSKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.0"),
        .package(path: "../CoreDomain")
    ],
    targets: [
        .target(
            name: "DSKit",
            dependencies: [.product(name: "OrderedCollections", package: "swift-collections"), "CoreDomain"],
            path: "Sources/DSKit",
            resources: [
                // Colors.xcassets is kept in main app for now — DSKit uses Color("...") which resolves via main bundle.
                // When fully isolated, move Colors.xcassets here and use Bundle.module.
            ]
        ),
        .testTarget(name: "DSKitTests", dependencies: ["DSKit"], path: "Tests/DSKitTests")
    ]
)
