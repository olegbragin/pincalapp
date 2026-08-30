// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CorePersistence",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "CorePersistence",
            targets: [
                "CorePersistence"
            ]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/objectbox/objectbox-swift-spm",
            from: "5.3.0"
        )
    ],
    targets: [
        .target(
            name: "CorePersistence",
            dependencies: [
                .product(name: "ObjectBox.xcframework", package: "objectbox-swift-spm")
            ],
            path: "Sources/CorePersistence"
        ),
        .testTarget(
            name: "CorePersistenceTests",
            dependencies: [
                "CorePersistence",
                .product(name: "ObjectBox.xcframework", package: "objectbox-swift-spm")
            ],
            path: "Tests/CorePersistenceTests"
        )
    ],
    swiftLanguageModes: [.v6],
)
