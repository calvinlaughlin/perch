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
        .target(name: "PerchCalendar", dependencies: ["PerchCore"]),
        .target(name: "PerchMedia", dependencies: ["PerchCore"]),
        .target(name: "PerchSystem", dependencies: ["PerchCore"]),
        .target(
            name: "PerchUI",
            dependencies: ["PerchCore", "PerchCalendar", "PerchMedia", "PerchSystem"]
        ),
        .executableTarget(
            name: "Perch",
            dependencies: ["PerchCore", "PerchCalendar", "PerchMedia", "PerchSystem", "PerchUI"]
        ),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchCalendarTests", dependencies: ["PerchCalendar"]),
        .testTarget(name: "PerchSystemTests", dependencies: ["PerchSystem"]),
        .testTarget(name: "PerchUITests", dependencies: ["PerchUI"]),
        .testTarget(
            name: "PerchMediaTests",
            dependencies: ["PerchMedia"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
