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
        .target(name: "PerchMedia", dependencies: ["PerchCore"]),
        .target(name: "PerchUI", dependencies: ["PerchCore", "PerchMedia"]),
        .executableTarget(name: "Perch", dependencies: ["PerchCore", "PerchMedia", "PerchUI"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchUITests", dependencies: ["PerchUI"]),
        .testTarget(
            name: "PerchMediaTests",
            dependencies: ["PerchMedia"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
