// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AreaMatrixIOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AreaMatrixIOS", targets: ["AreaMatrixIOS"]),
        .executable(name: "AreaMatrixIOSApp", targets: ["AreaMatrixIOSApp"])
    ],
    targets: [
        .systemLibrary(
            name: "Carea_matrixFFI",
            path: "Carea_matrixFFI"
        ),
        .target(
            name: "AreaMatrixIOS",
            dependencies: ["Carea_matrixFFI"],
            path: "AreaMatrix",
            linkerSettings: [
                .unsafeFlags([
                    "-L../../core/target/aarch64-apple-darwin/debug",
                    "-larea_matrix_core"
                ], .when(platforms: [.macOS])),
                .unsafeFlags([
                    "-L../../core/target/aarch64-apple-ios/debug",
                    "-larea_matrix_core"
                ], .when(platforms: [.iOS]))
            ]
        ),
        .executableTarget(
            name: "AreaMatrixIOSApp",
            dependencies: ["AreaMatrixIOS"],
            path: "AreaMatrixApp"
        ),
        .testTarget(
            name: "AreaMatrixIOSTests",
            dependencies: ["AreaMatrixIOS"],
            path: "AreaMatrixTests",
            exclude: ["Stage2ExperienceScopeTests.md"]
        )
    ]
)
