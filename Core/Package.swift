// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BreezeCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BreezeCore", targets: ["BreezeCore"]),
        .executable(name: "BreezeProbe", targets: ["BreezeProbe"])
    ],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "BreezeCore", dependencies: ["CSMC"]),
        .executableTarget(name: "BreezeProbe", dependencies: ["BreezeCore"]),
        .testTarget(name: "BreezeCoreTests", dependencies: ["BreezeCore"])
    ]
)
