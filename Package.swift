// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Avero",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "Avero", targets: ["AveroApp"]),
        .library(name: "AveroCore", targets: ["AveroCore"]),
        .library(name: "AveroCapture", targets: ["AveroCapture"]),
        .library(name: "AveroExport", targets: ["AveroExport"]),
    ],
    targets: [
        .executableTarget(
            name: "AveroApp",
            dependencies: [
                "AveroCore",
                "AveroCapture",
                "AveroExport",
            ]
        ),
        .target(name: "AveroCore"),
        .target(
            name: "AveroCapture",
            dependencies: ["AveroCore"]
        ),
        .target(
            name: "AveroExport",
            dependencies: ["AveroCore"]
        ),
        .testTarget(
            name: "AveroCoreTests",
            dependencies: ["AveroCore"]
        ),
    ]
)
