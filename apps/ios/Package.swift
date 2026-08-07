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
        .library(name: "AreaMatrixShareExtension", targets: ["AreaMatrixShareExtension"]),
        .executable(name: "AreaMatrixIOSApp", targets: ["AreaMatrixIOSApp"])
    ],
    dependencies: [
        .package(path: ".core-sdk")
    ],
    targets: [
        .target(
            name: "AreaMatrixIOS",
            dependencies: [
                .product(name: "AreaMatrixCoreSDK", package: ".core-sdk")
            ],
            path: "AreaMatrix"
        ),
        .executableTarget(
            name: "AreaMatrixIOSApp",
            dependencies: ["AreaMatrixIOS"],
            path: "AreaMatrixApp",
            exclude: [
                "AreaMatrixIOSApp.entitlements",
                "Info.plist"
            ]
        ),
        .target(
            name: "AreaMatrixShareExtension",
            dependencies: ["AreaMatrixIOS"],
            path: "AreaMatrixShareExtension",
            exclude: [
                "AreaMatrixShareExtension.entitlements",
                "Resources/Info.plist"
            ]
        ),
        .testTarget(
            name: "AreaMatrixIOSTests",
            dependencies: ["AreaMatrixIOS"],
            path: "AreaMatrixTests"
        )
    ]
)
