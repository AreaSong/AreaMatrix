import XCTest

private struct RetainedBridgeAdapter {
    let path: String
    let owner: String
    let reason: String
    let exitCondition: String
}

private enum BridgeGovernanceInventory {
    static let retainedAppOwnedAdapters: [RetainedBridgeAdapter] = [
        RetainedBridgeAdapter(
            path: "Bridge/CoreAIPrivacySnapshots.swift",
            owner: "AI",
            reason: "privacy and provider-scope semantics stay feature-owned",
            exitCondition: "extract only after privacy contracts are shared by two non-AI features"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreAISummaryMetadataReading.swift",
            owner: "AI",
            reason: "read-only SQLite projection is tied to summary recovery semantics",
            exitCondition: "move behind a shared read contract after a second summary consumer exists"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreClassifierRuleEditing.swift",
            owner: "Settings / FileActions",
            reason: "classifier editing combines localized drafts and recovery actions",
            exitCondition: "extract after classifier editor and another feature share the same value contract"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreClassifierRuleSavingAndImpactPreviewing.swift",
            owner: "Settings / FileActions",
            reason: "preview and save preserve classifier write confirmation semantics",
            exitCondition: "extract only with a second production caller and matching write-safety tests"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreExternalChangesSyncing.swift",
            owner: "MainList",
            reason: "FSEvents event normalization is coupled to MainList refresh policy",
            exitCondition: "extract after an independent feature consumes the same event contract"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreFileDeleting.swift",
            owner: "FileActions",
            reason: "delete and index removal have distinct user-file safety semantics",
            exitCondition: "extract only when both paths share a package contract without merging behavior"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreFileListing.swift",
            owner: "MainList / Detail",
            reason: "missing-file recovery and list projection share CoreBridge conversion helpers",
            exitCondition: "extract after list and recovery projections have independent shared callers"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreFileRenaming.swift",
            owner: "FileActions",
            reason: "rename carries confirmation and undo refresh behavior",
            exitCondition: "extract after another file-action surface consumes the same request contract"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreICloudConflictListing.swift",
            owner: "SyncConflicts",
            reason: "iCloud conflict presentation exposes placeholder and version uncertainty",
            exitCondition: "extract only with a second conflict feature and real placeholder evidence"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreImporting.swift",
            owner: "Import",
            reason: "import requests carry source URL, duplicate policy and trace context",
            exitCondition: "extract after a second import owner shares the contract without moving IO"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreImportConflictBatching.swift",
            owner: "Import",
            reason: "conflict batching is part of the import transaction and recovery flow",
            exitCondition: "extract after batch and folder import share a stable package contract"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreMetadataRepairing.swift",
            owner: "RepositoryLifecycle",
            reason: "repair operations are high-risk recovery actions with confirmation",
            exitCondition: "extract only after another recovery feature shares the same safety contract"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreNoteReadingWriting.swift",
            owner: "Detail / AI",
            reason: "note IO and AI summary operations have different privacy and revision semantics",
            exitCondition: "extract note-only contract after a second note consumer exists"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreObservabilityBridge.swift",
            owner: "Observability",
            reason: "callback sink adaptation and generated observability calls are process-scoped",
            exitCondition: "extract snapshots only after the callback boundary has an independent consumer"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreOverviewRegenerating.swift",
            owner: "RepositoryLifecycle",
            reason: "overview regeneration is a transactional staging and recovery workflow",
            exitCondition: "extract after another feature consumes the plan/session contract with the same gates"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreRemoteProviderConfiguring.swift",
            owner: "AI",
            reason: "credential lifecycle and privacy fallback state must stay within the AI boundary",
            exitCondition: "extract non-secret value contracts after a second provider feature shares them"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreSyncConflictDetecting.swift",
            owner: "SyncConflicts",
            reason: "conflict snapshots include file-system and iCloud uncertainty presentation",
            exitCondition: "extract after conflict detection has a second production consumer"
        ),
        RetainedBridgeAdapter(
            path: "Bridge/CoreSyncConflictResolving.swift",
            owner: "SyncConflicts",
            reason: "resolution performs user-file writes and must remain visibly high-risk",
            exitCondition: "do not extract until a shared write-safety contract and independent review exist"
        )
    ]
}

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
        XCTAssertFalse(source.contains("L10n."))
        XCTAssertFalse(source.contains("import area_matrix"))
        XCTAssertFalse(source.contains("import area_matrixFFI"))
    }

    func testCoreBridgeContractPackageOwnsChangeLogCapabilityContract() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("CoreChangeLogContracts.swift"),
            "Stable change-log capability contracts must live in the bridge contract package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreChangeLogContracts.swift"])
        XCTAssertTrue(source.contains("public protocol CoreChangeLogListing"))
        XCTAssertTrue(source.contains("public struct ChangeFilterSnapshot"))
        XCTAssertTrue(source.contains("public struct ChangeLogEntrySnapshot"))
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n."))
        XCTAssertFalse(source.contains("import area_matrix"))
        XCTAssertFalse(source.contains("import area_matrixFFI"))
    }

    func testCoreBridgeContractPackageOwnsCommandIndexCapabilityContract() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("CoreCommandIndexContracts.swift"),
            "Stable command-index capability contracts must live in the bridge contract package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreCommandIndexContracts.swift"])
        for declaration in [
            "public protocol CoreCommandIndexing",
            "public struct CommandIndexRequestSnapshot",
            "public struct CoreCommandIndexSnapshot",
            "public struct CoreCommandTargetSnapshot",
            "public enum CommandTargetGroupSnapshot",
            "public enum CommandTargetKindSnapshot",
            "public enum CommandTargetActionSnapshot"
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing shared command contract declaration: \(declaration)")
        }
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n"))
        XCTAssertFalse(source.contains("CommandIndex("))
    }

    func testCoreBridgeContractPackageOwnsClassificationCapabilityContract() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("CoreClassificationContracts.swift"),
            "Stable classification contract must live in the bridge contract package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreClassificationContracts.swift"])
        for declaration in [
            "public protocol CoreCategoryPredicting",
            "public enum ClassifyReasonSnapshot",
            "public struct ClassifyResultSnapshot"
        ] {
            XCTAssertTrue(
                source.contains(declaration),
                "Missing shared classification contract declaration: \(declaration)"
            )
        }
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n"))
        XCTAssertFalse(source.contains("ClassifyResult("))
    }

    func testCoreBridgeContractPackageOwnsUndoRedoCapabilityContract() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("CoreUndoRedoContracts.swift"),
            "Stable undo and redo capability contracts must live in the bridge contract package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreUndoRedoContracts.swift"])
        for declaration in [
            "public protocol CoreUndoActionLogging",
            "public protocol CoreRedoActionLogging",
            "public struct UndoActionRecordSnapshot",
            "public struct RedoActionRecordSnapshot"
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing shared undo/redo declaration: \(declaration)")
        }
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n"))
        XCTAssertFalse(source.contains("import area_matrix"))
        XCTAssertFalse(source.contains("import area_matrixFFI"))
    }

    func testCoreBridgeContractPackageOwnsAICallLogCapabilityContract() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("CoreAICallLogContracts.swift"),
            "Stable AI call-log contracts must live in the bridge contract package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreAICallLogContracts.swift"])
        for declaration in [
            "public protocol CoreAICallLogListing",
            "public protocol CoreAICallLogClearing",
            "public struct AICallLogFilterSnapshot",
            "public struct AICallLogRecordSnapshot",
            "public struct AICallLogPageSnapshot"
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing shared AI call-log declaration: \(declaration)")
        }
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n."))
        XCTAssertFalse(source.contains("import area_matrix"))
        XCTAssertFalse(source.contains("import area_matrixFFI"))
    }

    func testCoreBridgeContractPackageOwnsSearchFacetCapabilityContract() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("CoreSearchFacetContracts.swift"),
            "Stable search facet contracts must live in the bridge contract package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreSearchFacetContracts.swift"])
        for declaration in [
            "public protocol CoreSearchFiltering",
            "public enum SearchScopeSnapshot",
            "public struct SearchFilterStateSnapshot",
            "public struct SearchFacetRequestSnapshot",
            "public struct SearchFacetsSnapshot"
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing shared search facet declaration: \(declaration)")
        }
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertFalse(source.contains("import AppKit"))
        XCTAssertFalse(source.contains("L10n"))
        XCTAssertFalse(source.contains("import area_matrix"))
        XCTAssertFalse(source.contains("import area_matrixFFI"))
    }

    func testCoreBridgeContractPackageOwnsTagValueContracts() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertTrue(
            sourceFiles.map(\.lastPathComponent).contains("CoreTagContracts.swift")
                && sourceFiles.map(\.lastPathComponent).contains("CoreTagSuggestionContracts.swift"),
            "Stable tag and tag-suggestion contracts must live in the bridge contract package."
        )
        let sourceContents = try packageSourceContents("AreaMatrixCoreBridgeContract")
        let source = try XCTUnwrap(sourceContents["CoreTagContracts.swift"])
        for declaration in [
            "public struct AITagSuggestionRequestSnapshot",
            "public struct AITagSuggestionReportSnapshot",
            "public struct TagRecordSnapshot",
            "public struct TagSetSnapshot",
            "public struct BatchMutationReportSnapshot"
        ] {
            XCTAssertTrue(source.contains(declaration), "Missing shared tag contract declaration: \(declaration)")
        }
        let suggestionSource = try XCTUnwrap(sourceContents["CoreTagSuggestionContracts.swift"])
        for declaration in [
            "public protocol CoreTagCRUD",
            "public protocol CoreAITagSuggestionManaging",
            "public struct TagSuggestionRequestSnapshot",
            "public struct TagSuggestionReportSnapshot",
            "public struct TagSuggestionApplyReportSnapshot"
        ] {
            XCTAssertTrue(
                suggestionSource.contains(declaration),
                "Missing shared tag-suggestion contract declaration: \(declaration)"
            )
        }
        XCTAssertTrue(source.contains("Sendable"))
        XCTAssertTrue(suggestionSource.contains("Sendable"))
        XCTAssertFalse(source.contains("import Foundation"))
        XCTAssertFalse(suggestionSource.contains("import Foundation"))
        XCTAssertFalse(source.contains("import area_matrix"))
        XCTAssertFalse(source.contains("import area_matrixFFI"))
        XCTAssertFalse(suggestionSource.contains("import area_matrix"))
        XCTAssertFalse(suggestionSource.contains("import area_matrixFFI"))
    }

    func testCoreBridgeContractIsARealSwiftPackageBoundary() throws {
        let sourceFiles = try packageSwiftFiles("AreaMatrixCoreBridgeContract")
        XCTAssertEqual(
            sourceFiles.map(\.lastPathComponent).sorted(),
            [
                "CoreAICallLogContracts.swift",
                "CoreBridgeBoundary.swift",
                "CoreBridgeCapabilityContracts.swift",
                "CoreBridgeRuntimeContract.swift",
                "CoreChangeLogContracts.swift",
                "CoreClassificationContracts.swift",
                "CoreCommandIndexContracts.swift",
                "CoreDiagnosticsContracts.swift",
                "CoreRepositoryContracts.swift",
                "CoreSearchFacetContracts.swift",
                "CoreTagContracts.swift",
                "CoreTagSuggestionContracts.swift",
                "CoreUndoRedoContracts.swift"
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

    func testRetainedAppOwnedBridgeAdaptersHaveExplicitExitConditions() throws {
        let retainedAdapters = BridgeGovernanceInventory.retainedAppOwnedAdapters
        let productionFiles = try productionSwiftFiles()
        let existingPaths = Set(productionFiles.map { relativeProductionPath(for: $0) })
        let missing = retainedAdapters.compactMap { item in
            existingPaths.contains(item.path) ? nil : item.path
        }
        XCTAssertEqual(missing, [], "Retained Bridge adapters must stay present in the App target.")

        let incomplete = retainedAdapters.compactMap { item -> String? in
            let fields = [item.owner, item.reason, item.exitCondition]
            return fields.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                ? nil
                : item.path
        }
        XCTAssertEqual(
            incomplete,
            [],
            "Every retained App-owned Bridge adapter needs an owner, reason and exit condition."
        )
    }
}
