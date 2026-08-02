// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AreaMatrixModules",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AreaMatrixCoreContracts", targets: ["AreaMatrixCoreContracts"]),
        .library(name: "AreaMatrixCoreBridgeContract", targets: ["AreaMatrixCoreBridgeContract"]),
        .library(name: "AreaMatrixUIFoundation", targets: ["AreaMatrixUIFoundation"]),
        .library(name: "AreaMatrixPlatformKit", targets: ["AreaMatrixPlatformKit"])
    ],
    targets: [
        .target(
            name: "AreaMatrixCoreContracts",
            path: "Sources/AreaMatrixCoreContracts"
        ),
        .target(
            name: "AreaMatrixCoreBridgeContract",
            path: "Sources/AreaMatrixCoreBridgeContract"
        ),
        .target(
            name: "AreaMatrixUIFoundation",
            path: "Sources/AreaMatrixUIFoundation"
        ),
        .target(
            name: "AreaMatrixPlatformKit",
            path: "Sources/AreaMatrixPlatformKit"
        ),
        .testTarget(
            name: "AreaMatrixCoreContractsTests",
            dependencies: ["AreaMatrixCoreContracts"],
            path: "Tests/AreaMatrixCoreContractsTests"
        ),
        .testTarget(
            name: "AreaMatrixCoreBridgeContractTests",
            dependencies: ["AreaMatrixCoreBridgeContract"],
            path: "Tests/AreaMatrixCoreBridgeContractTests"
        ),
        .testTarget(
            name: "AreaMatrixUIFoundationTests",
            dependencies: ["AreaMatrixUIFoundation"],
            path: "Tests/AreaMatrixUIFoundationTests"
        ),
        .testTarget(
            name: "AreaMatrixPlatformKitTests",
            dependencies: ["AreaMatrixPlatformKit"],
            path: "Tests/AreaMatrixPlatformKitTests"
        )
    ]
)
