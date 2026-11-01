// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BruaKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "BruaKit", targets: ["BruaKit"]),
    ],
    targets: [
        .target(name: "BruaKit"),
        .testTarget(name: "BruaKitTests", dependencies: ["BruaKit"]),
    ]
)
