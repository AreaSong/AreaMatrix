import XCTest

final class MainRepositoryRouteHostGovernanceTests: MacOSGovernanceTestCase {
    func testLifecycleComposesFeatureOwnedRouteHostsWithoutOwningSheetBuilders() throws {
        let lifecycleSource = try mainRepositoryContentLifecycleSource()
        let expectedFeatureHosts = [
            "applyMainRepositoryPrimaryFileActionSheet",
            "applyMainRepositorySearchSheets",
            "applyMainRepositoryBatchFileActionSheets",
            "applyMainRepositorySmartListSheet",
            "applyMainRepositorySyncConflictSheet",
            "applyMainRepositoryImportConflictBatchRelay"
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

        XCTAssertTrue(importRoutingSource.contains("func applyMainRepositoryImportConflictBatchRelay("))
        XCTAssertTrue(importRoutingSource.contains("struct ImportConflictBatchRelayState"))
        XCTAssertTrue(importRoutingSource.contains("consumePendingRoute()"))
        XCTAssertTrue(importRoutingSource.contains("onOpenImportConflictBatch(route)"))

        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let commandPaletteSource = try productionSource(
            at: "Features/CommandPalette/CommandPaletteRoutingSupport.swift"
        )
        XCTAssertTrue(contentSource.contains("ImportConflictBatchRelayState()"))
        XCTAssertFalse(contentSource.contains("@State var pendingImportConflictBatchRoute"))
        XCTAssertTrue(commandPaletteSource.contains("importConflictBatchRelayState.enqueue(route)"))
        XCTAssertFalse(commandPaletteSource.contains("pendingImportConflictBatchRoute = route"))
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

        XCTAssertTrue(contentSource.contains("CommandPaletteFocusRoutingState()"))
        XCTAssertFalse(contentSource.contains("restoreSearchFocusAfterPalette"))
        XCTAssertTrue(commandPaletteSource.contains("struct CommandPaletteFocusRoutingState"))
        XCTAssertTrue(commandPaletteSource.contains("func consumeSearchFieldFocusRestoration() -> Bool"))
    }

    func testSearchPresentationRoutingStateStaysOwnedBySearchFeature() throws {
        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let searchRoutingSource = try productionSource(
            at: "Features/Search/MainRepositoryContentSearchRouting.swift"
        )

        XCTAssertTrue(contentSource.contains("MainRepositorySearchRoutingState()"))
        XCTAssertFalse(contentSource.contains("@State var isSearchFiltersPresented"))
        XCTAssertFalse(contentSource.contains("@State var isSidebarTagsFilterPresented"))
        XCTAssertFalse(contentSource.contains("@State var smartListManagementRoute"))
        XCTAssertTrue(searchRoutingSource.contains("struct MainRepositorySearchRoutingState"))
    }

    func testFileActionPresentationRoutingStateStaysOwnedByFileActionsFeature() throws {
        let contentSource = try productionSource(at: "Views/Main/MainRepositoryContentView.swift")
        let fileActionStateSource = try productionSource(
            at: "Features/FileActions/MainFileActionRoutingState.swift"
        )

        XCTAssertTrue(contentSource.contains("MainFileActionRoutingState()"))
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
        let syncConflictSource = try productionSource(
            at: "Features/SyncConflicts/SyncConflictReviewSupportViews.swift"
        )
        let detailSource = try productionSource(
            at: "Features/Detail/MainRepositoryContentDetailSupport.swift"
        )

        XCTAssertTrue(syncConflictSource.contains("func syncConflictReviewSheet("))
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
