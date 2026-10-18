// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HHTCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HHTCore", targets: ["HHTCore"]),
        .executable(name: "hht-calibrate", targets: ["hht-calibrate"]),
    ],
    targets: [
        .target(name: "HHTCore"),
        .executableTarget(name: "hht-calibrate", dependencies: ["HHTCore"]),
        .testTarget(name: "HHTCoreTests", dependencies: ["HHTCore"]),
    ]
)
