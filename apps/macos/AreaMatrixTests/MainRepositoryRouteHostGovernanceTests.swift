import XCTest

final class MainRepositoryRouteHostGovernanceTests: MacOSGovernanceTestCase {
    func testLifecycleComposesFeatureOwnedRouteHostsWithoutOwningSheetBuilders() throws {
        let lifecycleSource = try mainRepositoryContentLifecycleSource()
        let expectedFeatureHosts = [
            "applyMainRepositoryPrimaryFileActionSheet",
            "applyMainRepositorySearchSheets",
            "applyMainRepositoryBatchFileActionSheets",
            "applyMainRepositorySmartListSheet",
            "SyncConflictReviewHostModifier",
            "mainRepositoryImportConflictBatchRelay"
        ]
        let featureOwnedSheetBuilders = [
            "actionRoutingSheet",
            "searchRoutingSheet",
            "semanticPrivacyRuleSheet",
            "semanticCallLogSheet",
            "batchAddTagsRoutingSheet",
            "batchChangeCategoryRoutingSheet",
            "batchDeleteRoutingSheet",
            "batchRenameRoutingSheet",
            "undoHistorySheet",
            "smartListManagementSheet",
            "syncConflictReviewSheet"
        ]

        for host in expectedFeatureHosts {
            XCTAssertTrue(
                lifecycleSource.contains(host),
                "MainRepositoryContentLifecycle must compose the feature-owned route host: \(host)."
            )
        }
        for sheetBuilder in featureOwnedSheetBuilders {
            XCTAssertFalse(
                lifecycleSource.contains(sheetBuilder),
                "Feature-specific sheet builder must stay with its feature owner: \(sheetBuilder)."
            )
        }
        XCTAssertFalse(lifecycleSource.contains("pendingImportConflictBatchRoute"))
        XCTAssertFalse(lifecycleSource.contains("onOpenImportConflictBatch(route)"))
    }

    func testImportConflictBatchRelayStaysOwnedByImportFeature() throws {
        let importRoutingSource = try productionSource(
            at: "Features/Import/MainRepositoryContentImportRouting.swift"
        )

        XCTAssertTrue(importRoutingSource.contains("struct ImportConflictBatchRelayModifier"))
        XCTAssertTrue(importRoutingSource.contains("func mainRepositoryImportConflictBatchRelay("))
        XCTAssertTrue(importRoutingSource.contains("struct ImportConflictBatchRelayState"))
        XCTAssertTrue(importRoutingSource.contains("consumePendingRoute()"))
        XCTAssertTrue(importRoutingSource.contains("onOpen(route)"))

        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let commandPaletteModelSource = try productionSource(
            at: "Features/CommandPalette/CommandPaletteState.swift"
        )
        let commandPaletteSource = try productionSource(
            at: "Features/CommandPalette/CommandPaletteRoutingSupport.swift"
        )
        XCTAssertTrue(contentSource.contains("@StateObject var commandPaletteModel: CommandPaletteModel"))
        XCTAssertTrue(commandPaletteModelSource
            .contains("importConflictBatchRelayState = ImportConflictBatchRelayState()"))
        XCTAssertFalse(contentSource.contains("@State var pendingImportConflictBatchRoute"))
        XCTAssertTrue(commandPaletteSource.contains("importConflictBatchRelayState.enqueue(route)"))
        XCTAssertFalse(commandPaletteSource.contains("pendingImportConflictBatchRoute = route"))
    }

    func testImportProgressListContractStaysOwnedByImportFeature() throws {
        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let lifecycleSource = try mainRepositoryContentLifecycleSource()
        let importProgressSource = try productionSource(
            at: "Features/Import/ImportProgressListIntegration.swift"
        )

        XCTAssertTrue(contentSource.contains("ImportProgressListPresentation"))
        XCTAssertTrue(contentSource.contains("ImportProgressListSelectionState()"))
        XCTAssertFalse(contentSource.contains("let importProgressItems:"))
        XCTAssertFalse(contentSource.contains("@State var selectedImportProgressIDs"))
        XCTAssertTrue(importProgressSource.contains("struct ImportProgressListPresentation"))
        XCTAssertTrue(importProgressSource.contains("struct ImportProgressListSelectionState"))
        XCTAssertTrue(importProgressSource.contains("func applyMainRepositoryImportProgressSelectionRelay("))
        XCTAssertFalse(lifecycleSource.contains("onChange(of: selectedImportProgressIDs)"))
    }

    func testMainListErrorRecoveryActionsStayOwnedByMainListFeature() throws {
        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let recoverySource = try productionSource(at: "Features/MainList/MainCurrentListErrorPane.swift")

        XCTAssertTrue(contentSource.contains("MainListErrorRecoveryActions"))
        XCTAssertFalse(contentSource.contains("let onRetryCurrentList:"))
        XCTAssertFalse(contentSource.contains("let onCollectDiagnostics:"))
        XCTAssertTrue(recoverySource.contains("struct MainListErrorRecoveryActions"))
        XCTAssertTrue(recoverySource.contains("fileListModel.currentListDiagnostics.requestCollection()"))
    }

    func testLifecycleComposesFeatureOwnedCommandHostsInExistingModifierOrder() throws {
        let lifecycleSource = try mainRepositoryContentLifecycleSource()
        let expectedCommandHosts = [
            "applyMainRepositoryUndoHistoryMenuCommandRelay",
            "applyMainRepositoryCommandPaletteMenuCommandRelay",
            "applyMainRepositoryUndoRedoKeyCommands"
        ]
        let hostPositions = try expectedCommandHosts.map { host in
            try XCTUnwrap(lifecycleSource.range(of: host)?.lowerBound)
        }

        XCTAssertEqual(hostPositions, hostPositions.sorted())
        XCTAssertFalse(lifecycleSource.contains("AreaMatrixUndoHistoryCommandRelay.notification"))
        XCTAssertFalse(lifecycleSource.contains("AreaMatrixCommandPaletteCommandRelay.notification"))
        XCTAssertFalse(lifecycleSource.contains(".onKeyPress(\"z\""))
    }

    func testFeatureCommandHostsStayWithTheirOwners() throws {
        let undoHistorySource = try productionSource(
            at: "Features/FileActions/MainRepositoryContentUndoHistory.swift"
        )
        let commandPaletteSource = try productionSource(
            at: "Features/CommandPalette/MainRepositoryContentCommandPaletteActions.swift"
        )

        XCTAssertTrue(undoHistorySource.contains("func applyMainRepositoryUndoHistoryMenuCommandRelay("))
        XCTAssertTrue(undoHistorySource.contains("func applyMainRepositoryUndoRedoKeyCommands("))
        XCTAssertTrue(commandPaletteSource.contains("func applyMainRepositoryCommandPaletteMenuCommandRelay("))
    }

    func testCommandPaletteFocusRestorationStateStaysOwnedByCommandPaletteFeature() throws {
        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let commandPaletteSource = try productionSource(
            at: "Features/CommandPalette/CommandPaletteRoutingSupport.swift"
        )
        let commandPaletteModelSource = try productionSource(
            at: "Features/CommandPalette/CommandPaletteState.swift"
        )

        XCTAssertTrue(contentSource.contains("@StateObject var commandPaletteModel: CommandPaletteModel"))
        XCTAssertFalse(contentSource.contains("restoreSearchFocusAfterPalette"))
        XCTAssertTrue(commandPaletteModelSource.contains("focusRoutingState = CommandPaletteFocusRoutingState()"))
        XCTAssertTrue(commandPaletteSource.contains("struct CommandPaletteFocusRoutingState"))
        XCTAssertTrue(commandPaletteSource.contains("func consumeSearchFieldFocusRestoration() -> Bool"))
    }

    func testSearchPresentationRoutingStateStaysOwnedBySearchFeature() throws {
        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let searchRoutingSource = try productionSource(
            at: "Features/Search/MainRepositoryContentSearchRouting.swift"
        )
        let searchModelSource = try productionSource(at: "Features/Search/SearchModel.swift")
        let lifecycleSource = try mainRepositoryContentLifecycleSource()

        XCTAssertTrue(contentSource.contains("@StateObject var searchModel: SearchModel"))
        XCTAssertTrue(searchModelSource.contains("routingState = MainRepositorySearchRoutingState()"))
        XCTAssertFalse(contentSource.contains("@State var isSearchFiltersPresented"))
        XCTAssertFalse(contentSource.contains("@State var isSidebarTagsFilterPresented"))
        XCTAssertFalse(contentSource.contains("@State var smartListManagementRoute"))
        XCTAssertFalse(contentSource.contains("@State var isSemanticIndexConfirmationPresented"))
        XCTAssertFalse(contentSource.contains("@State var semanticPrivacyRuleRoute"))
        XCTAssertFalse(contentSource.contains("@State var semanticCallLogRoute"))
        XCTAssertTrue(searchRoutingSource.contains("struct MainRepositorySearchRoutingState"))
        XCTAssertTrue(searchRoutingSource.contains("func applyMainRepositoryContentSearchTasks("))
        XCTAssertTrue(searchRoutingSource.contains("func applyMainRepositorySemanticIndexDialogs("))
        XCTAssertFalse(lifecycleSource.contains(".task(id: searchTaskKey)"))
        XCTAssertFalse(lifecycleSource.contains(".task(id: searchFacetsTaskKey)"))
        XCTAssertFalse(lifecycleSource.contains("\"Build semantic index?\""))
        XCTAssertFalse(lifecycleSource.contains("\"Cancel semantic index build?\""))
    }

    func testFileActionPresentationRoutingStateStaysOwnedByFileActionsFeature() throws {
        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let fileActionStateSource = try productionSource(
            at: "Features/FileActions/MainFileActionRoutingState.swift"
        )
        let fileActionCoordinatorSource = try productionSource(
            at: "Features/FileActions/FileActionCoordinator.swift"
        )

        XCTAssertTrue(contentSource.contains("@StateObject var fileActionCoordinator: FileActionCoordinator"))
        XCTAssertTrue(fileActionCoordinatorSource.contains("routingState = MainFileActionRoutingState()"))
        XCTAssertFalse(contentSource.contains("@State var pendingBatchAddTagsRoute"))
        XCTAssertFalse(contentSource.contains("@State var pendingBatchChangeCategoryRoute"))
        XCTAssertFalse(contentSource.contains("@State var pendingBatchDeleteRoute"))
        XCTAssertFalse(contentSource.contains("@State var pendingBatchRenameRoute"))
        XCTAssertFalse(contentSource.contains("@State var pendingUndoHistoryRequest"))
        XCTAssertFalse(contentSource.contains("@State var batchTagUndoState"))
        XCTAssertFalse(contentSource.contains("@State var batchTagActionLogRefreshFailure"))
        XCTAssertTrue(fileActionStateSource.contains("struct MainFileActionRoutingState"))
    }

    func testSyncConflictReviewSheetStaysOwnedBySyncConflictsFeature() throws {
        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let syncConflictSource = try productionSource(
            at: "Features/SyncConflicts/SyncConflictReviewSupportViews.swift"
        )
        let detailSource = try productionSource(
            at: "Features/Detail/MainRepositoryContentDetailSupport.swift"
        )

        let syncCoordinatorSource = try productionSource(
            at: "Features/SyncConflicts/SyncConflictCoordinator.swift"
        )

        XCTAssertTrue(syncConflictSource.contains("struct SyncConflictReviewHostModifier: ViewModifier"))
        XCTAssertTrue(syncConflictSource.contains("private func reviewSheet("))
        XCTAssertTrue(syncConflictSource.contains("struct SyncConflictReviewRoutingState"))
        XCTAssertTrue(contentSource.contains("@StateObject var syncConflictCoordinator: SyncConflictCoordinator"))
        XCTAssertTrue(syncCoordinatorSource.contains("reviewRoutingState = SyncConflictReviewRoutingState()"))
        XCTAssertFalse(contentSource.contains("@State var pendingSyncConflictReviewRoute"))
        XCTAssertFalse(
            detailSource.contains("func syncConflictReviewSheet("),
            "Sync conflict review routing must not drift back into the Detail feature."
        )
    }

    private func mainRepositoryContentLifecycleSource() throws -> String {
        try productionSource(at: "Views/Main/MainRepositoryContentLifecycle.swift")
    }

    private func productionSource(at relativePath: String) throws -> String {
        let file = try XCTUnwrap(productionSwiftFiles().first {
            relativeProductionPath(for: $0) == relativePath
        })
        return try String(contentsOf: file, encoding: .utf8)
    }
}
