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
        .library(name: "AreaMatrixCoreBridgeRuntime", targets: ["AreaMatrixCoreBridgeRuntime"]),
        .library(name: "AreaMatrixUIFoundation", targets: ["AreaMatrixUIFoundation"]),
        .library(name: "AreaMatrixPlatformKit", targets: ["AreaMatrixPlatformKit"]),
        .library(name: "AreaMatrixFeatureLibrary", targets: ["AreaMatrixFeatureLibrary"]),
        .library(name: "AreaMatrixFeatureIngestion", targets: ["AreaMatrixFeatureIngestion"]),
        .library(name: "AreaMatrixFeatureOperation", targets: ["AreaMatrixFeatureOperation"]),
        .library(name: "AreaMatrixFeatureSettings", targets: ["AreaMatrixFeatureSettings"]),
        .library(name: "AreaMatrixFeatureAI", targets: ["AreaMatrixFeatureAI"])
    ],
    targets: [
        .target(
            name: "AreaMatrixCoreContracts",
            path: "Sources/AreaMatrixCoreContracts"
        ),
        .target(
            name: "AreaMatrixCoreBridgeContract",
            dependencies: ["AreaMatrixCoreContracts"],
            path: "Sources/AreaMatrixCoreBridgeContract"
        ),
        .target(
            name: "AreaMatrixCoreBridgeRuntime",
            dependencies: ["AreaMatrixCoreBridgeContract"],
            path: "Sources/AreaMatrixCoreBridgeRuntime"
        ),
        .target(
            name: "AreaMatrixUIFoundation",
            path: "Sources/AreaMatrixUIFoundation"
        ),
        .target(
            name: "AreaMatrixPlatformKit",
            path: "Sources/AreaMatrixPlatformKit"
        ),
        .target(
            name: "AreaMatrixFeatureLibrary",
            dependencies: ["AreaMatrixCoreContracts", "AreaMatrixCoreBridgeContract"],
            path: "Sources/AreaMatrixFeatureLibrary"
        ),
        .target(
            name: "AreaMatrixFeatureIngestion",
            dependencies: ["AreaMatrixCoreContracts", "AreaMatrixUIFoundation"],
            path: "Sources/AreaMatrixFeatureIngestion"
        ),
        .target(
            name: "AreaMatrixFeatureOperation",
            dependencies: ["AreaMatrixCoreContracts"],
            path: "Sources/AreaMatrixFeatureOperation"
        ),
        .target(
            name: "AreaMatrixFeatureSettings",
            dependencies: ["AreaMatrixCoreContracts"],
            path: "Sources/AreaMatrixFeatureSettings"
        ),
        .target(
            name: "AreaMatrixFeatureAI",
            dependencies: ["AreaMatrixCoreContracts"],
            path: "Sources/AreaMatrixFeatureAI"
        ),
        .testTarget(
            name: "AreaMatrixCoreContractsTests",
            dependencies: ["AreaMatrixCoreContracts"],
            path: "Tests/AreaMatrixCoreContractsTests"
        ),
        .testTarget(
            name: "AreaMatrixCoreBridgeContractTests",
            dependencies: ["AreaMatrixCoreBridgeContract", "AreaMatrixCoreContracts"],
            path: "Tests/AreaMatrixCoreBridgeContractTests"
        ),
        .testTarget(
            name: "AreaMatrixCoreBridgeRuntimeTests",
            dependencies: ["AreaMatrixCoreBridgeRuntime", "AreaMatrixCoreBridgeContract"],
            path: "Tests/AreaMatrixCoreBridgeRuntimeTests"
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
        ),
        .testTarget(
            name: "AreaMatrixFeatureModulesTests",
            dependencies: [
                "AreaMatrixFeatureLibrary",
                "AreaMatrixCoreBridgeContract",
                "AreaMatrixFeatureIngestion",
                "AreaMatrixFeatureOperation",
                "AreaMatrixFeatureSettings",
                "AreaMatrixFeatureAI"
            ],
            path: "Tests/AreaMatrixFeatureModulesTests"
        )
    ]
)
