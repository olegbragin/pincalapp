// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CoreDomain",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CoreDomain", targets: ["CoreDomain"])
    ],
    targets: [
        .target(name: "CoreDomain", path: "Sources/CoreDomain"),
        .testTarget(name: "CoreDomainTests", dependencies: ["CoreDomain"], path: "Tests/CoreDomainTests")
    ]
)
