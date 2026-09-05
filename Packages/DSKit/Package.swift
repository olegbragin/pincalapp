// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DSKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "DSKit",
            targets: [
                "DSKit"
            ]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-collections.git",
            from: "1.5.0"
        ),
        .package(
            path: "../CoreDomain"
        )
    ],
    targets: [
        .target(
            name: "DSKit",
            dependencies: [
                .product(name: "OrderedCollections", package: "swift-collections"),
                "CoreDomain"
            ],
            path: "Sources/DSKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "DSKitTests",
            dependencies: [
                "DSKit",
                "CoreDomain"
            ],
            path: "Tests/DSKitTests"
        )
    ],
    swiftLanguageModes: [.v6],
)
