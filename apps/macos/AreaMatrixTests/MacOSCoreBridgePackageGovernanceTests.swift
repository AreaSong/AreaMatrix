import XCTest

extension MacOSArchitectureBoundaryGovernanceTests {
    func testCoreContractsPackageOwnsBindingContractSnapshots() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreContracts")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("BindingContractSnapshots.swift"),
            "Stable binding contract snapshots must live in the shared contracts package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreContracts")
        let source = try XCTUnwrap(sourceContents["BindingContractSnapshots.swift"])
        for declaration in [
            "public enum BindingTargetPlatformSnapshot",
            "public enum BindingSupportStatusSnapshot",
            "public struct BindingApiContractSnapshot",
            "public struct BindingTypeMappingSnapshot",
            "public struct BindingMissingCapabilitySnapshot",
            "public struct BindingContractReportSnapshot"
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing shared contract declaration: \(declaration)")
        }
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n"))
        XCTAssertFalse(source.contains("BindingContractReport("))
    }

    func testCoreContractsPackageOwnsPlatformCapabilitySnapshots() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreContracts")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("PlatformCapabilitySnapshots.swift"),
            "Stable platform capability snapshots must live in the shared contracts package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreContracts")
        let source = try XCTUnwrap(sourceContents["PlatformCapabilitySnapshots.swift"])
        for declaration in [
            "public enum PlatformIdSnapshot",
            "public enum PlatformCapabilityStatusSnapshot",
            "public struct PlatformCapabilitySupportSnapshot",
            "public struct PlatformCapabilitiesSnapshot"
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing shared contract declaration: \(declaration)")
        }
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n"))
        XCTAssertFalse(source.contains("PlatformCapabilities("))
    }

    func testCoreBridgeContractPackageOwnsDiagnosticsCapabilityContract() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("CoreDiagnosticsContracts.swift"),
            "Stable diagnostics capability contracts must live in the bridge contract package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreDiagnosticsContracts.swift"])
        XCTAssertTrue(source.contains("public protocol CoreDiagnosticsCollecting"))
        XCTAssertTrue(source.contains("public struct DiagnosticsSnapshotSnapshot"))
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n"))
        XCTAssertFalse(source.contains("DiagnosticsSnapshot("))
    }

    func testCoreBridgeContractIsARealSwiftPackageBoundary() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertEqual(
            sourceFiles.map(\.lastPathComponent).sorted(),
            [
                "CoreBridgeBoundary.swift",
                "CoreBridgeCapabilityContracts.swift",
                "CoreBridgeRuntimeContract.swift",
                "CoreDiagnosticsContracts.swift"
            ],
            "The bridge contract package must remain a small, generated-binding-free contract boundary."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(sourceContents["CoreBridgeBoundary.swift"]?.contains("public enum CoreBridgeBoundary") == true)
        XCTAssertTrue(
            sourceContents["CoreBridgeRuntimeContract.swift"]?
                .contains("public protocol CoreBridgeRuntimeProviding") == true
                && sourceContents["CoreBridgeRuntimeContract.swift"]?.contains("CoreBridgeRuntimeState") == true
                && sourceContents["CoreBridgeRuntimeContract.swift"]?.contains("Sendable") == true
        )
        let packageProject = testsDirectory()
            .deletingLastPathComponent()
            .appendingPathComponent("AreaMatrix.xcodeproj/project.pbxproj")
        let projectSource = try String(contentsOf: packageProject, encoding: .utf8)
        XCTAssertTrue(projectSource.contains("AreaMatrixCoreBridgeContract in Frameworks"))
        XCTAssertTrue(projectSource.contains("productName = AreaMatrixCoreBridgeContract;"))

        let runtimeSourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeRuntime")
        XCTAssertEqual(
            runtimeSourceFiles.map(\.lastPathComponent).sorted(),
            ["CoreBridgeRuntimeCoordinator.swift"]
        )
        let runtimeContents = try packageSourceContents("AreaMatrixCoreBridgeRuntime")
        XCTAssertTrue(
            runtimeContents["CoreBridgeRuntimeCoordinator.swift"]?.contains(
                "public actor CoreBridgeRuntimeCoordinator"
            ) == true
        )
        XCTAssertTrue(projectSource.contains("AreaMatrixCoreBridgeRuntime in Frameworks"))
        XCTAssertTrue(projectSource.contains("productName = AreaMatrixCoreBridgeRuntime;"))
    }
}
