// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "perch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "perch", targets: ["Perch"])
    ],
    targets: [
        .target(name: "PerchCore"),
        .target(name: "PerchUI", dependencies: ["PerchCore"]),
        .executableTarget(name: "Perch", dependencies: ["PerchCore", "PerchUI"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchUITests", dependencies: ["PerchUI"]),
    ]
)
