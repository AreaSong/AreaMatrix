@testable import AreaMatrix
import AreaMatrixCoreBridgeContract
import AreaMatrixCoreBridgeRuntime
import XCTest

final class CoreBridgeBoundaryGovernanceTests: MacOSGovernanceTestCase {
    func testCoreBridgeGeneratedCallsStayBehindPhysicalAdapter() throws {
        let bridgeSource = try String(
            contentsOf: XCTUnwrap(productionSwiftFiles().first {
                relativeProductionPath(for: $0) == "Bridge/CoreBridge.swift"
            }),
            encoding: .utf8
        )
        let adapterFile = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == "Bridge/CoreBridgeGeneratedAdapter.swift"
        })
        let adapterSource = try String(contentsOf: adapterFile, encoding: .utf8)

        XCTAssertTrue(adapterSource.contains("struct CoreBridgeGeneratedAdapter"))
        for generatedCall in [
            "try loadRepoConfig(",
            "try updateRepoConfig(",
            "try validateRepoPath(repoPath:",
            "try validateInitializedRepoPath(repoPath:",
            "try getLatestScanSession(",
            "try resumeScanSession(repoPath:",
            "try predictCategory(repoPath:",
            "try createDiagnosticsSnapshot(repoPath:",
            "try listFiles(repoPath:",
            "try getFile(repoPath:",
            "try listTreeJson(repoPath:",
            "try listCommandTargets(repoPath:",
            "try AreaMatrix.listAiCalls(",
            "try AreaMatrix.clearAiCallLog("
        ] {
            XCTAssertTrue(
                adapterSource.contains(generatedCall),
                "Generated Core call must stay in CoreBridgeGeneratedAdapter: \(generatedCall)"
            )
            XCTAssertFalse(
                bridgeSource.contains(generatedCall),
                "CoreBridge runtime actor must not own first-order generated calls: \(generatedCall)"
            )
        }
    }

    func testReadOnlyBridgeExtensionsUseThePhysicalAdapter() throws {
        let guardedPaths = Set([
            "Bridge/CorePlatformCapabilitiesLoading.swift",
            "Bridge/CoreBindingContractInspecting.swift",
            "Bridge/CoreChangeLogListing.swift",
            "Bridge/CoreSearchQuerying.swift",
            "Bridge/CoreAICallLogSnapshots.swift",
            "Bridge/CoreSearchFacetSnapshots.swift"
        ])
        let sources = try productionSwiftFiles()
            .filter { guardedPaths.contains(relativeProductionPath(for: $0)) }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for generatedCall in [
            "try getPlatformCapabilities(",
            "try inspectBindingContract(",
            "try listChanges(",
            "try searchFiles(",
            "try listFilterFacets(",
            "try listAiCalls(",
            "try clearAiCallLog("
        ] {
            XCTAssertFalse(
                sources.contains(generatedCall),
                "Read-only bridge extensions must call CoreBridgeGeneratedAdapter instead of "
                    + "generated bindings: \(generatedCall)"
            )
        }
    }

    func testGeneratedAdapterRejectsUndeclaredBoundaryBeforeUniFFIInvocation() async throws {
        let runtime = CoreBridgeRuntimeCoordinator(boundaries: [.getVersion])
        let bridge = CoreBridge(runtimeCoordinator: runtime)

        do {
            _ = try await bridge.loadConfig(repoPath: "/unreachable")
            XCTFail("An undeclared boundary must fail before generated bindings are invoked.")
        } catch let error as CoreBridgeRuntimeError {
            XCTAssertEqual(error, .undeclaredBoundary(.loadConfig))
        }
    }
}
