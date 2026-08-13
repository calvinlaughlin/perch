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
        .target(name: "PerchAgents", dependencies: ["PerchCore"]),
        .target(name: "PerchUI", dependencies: ["PerchCore", "PerchMedia", "PerchAgents"]),
        .executableTarget(
            name: "Perch", dependencies: ["PerchCore", "PerchMedia", "PerchAgents", "PerchUI"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchAgentsTests", dependencies: ["PerchAgents"]),
        .testTarget(name: "PerchUITests", dependencies: ["PerchUI"]),
        .testTarget(
            name: "PerchMediaTests",
            dependencies: ["PerchMedia"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
