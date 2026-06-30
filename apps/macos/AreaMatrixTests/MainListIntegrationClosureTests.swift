@testable import AreaMatrix
import XCTest

final class MainListIntegrationClosureTests: XCTestCase {
    @MainActor
    func testMultiSelectionRoutesToDetailMultiAndRefreshesSelectedDetails() async {
        let docsFile = FileEntrySnapshot.integrationClosureFixture(id: 1, currentName: "a.pdf")
        let financeFile = FileEntrySnapshot.integrationClosureFixture(id: 2, currentName: "b.pdf")
        let detailer = MainListIntegrationDetailer(results: [.success(docsFile), .success(financeFile)])
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [docsFile, financeFile]),
            fileLister: NoopFileLister(),
            fileDetailer: detailer,
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([docsFile.id, financeFile.id])
        let detailRequests = await detailer.recordedRequests()

        XCTAssertEqual(model.selection, .multiple([docsFile.id, financeFile.id]))
        XCTAssertNil(model.selectedFileDetail)
        XCTAssertNil(model.detailErrorMapping)
        XCTAssertEqual(detailRequests, [docsFile.id, financeFile.id])
    }

    @MainActor
    func testSingleFileContextActionsRouteToSheetsWithoutCallingControlMapOutOfScopeCore() async {
        let docsFile = FileEntrySnapshot.integrationClosureFixture(id: 7, currentName: "a.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [docsFile]),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(docsFile)]),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([docsFile.id])
        model.beginRename()
        XCTAssertEqual(model.pendingActionDestination, .rename(fileID: docsFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "rename-file")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Rename File")

        model.beginChangeCategory()
        XCTAssertEqual(model.pendingActionDestination, .changeCategory(fileID: docsFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "change-category")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Change Category")

        model.beginClassifierCorrection()
        XCTAssertEqual(
            model.pendingActionDestination,
            .changeCategory(fileID: docsFile.id, mode: .classifierCorrection)
        )
        XCTAssertEqual(model.pendingActionDestination?.pageID, "classifier-correction")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Correct Classification")

        model.beginAIClassificationSuggestion()
        XCTAssertEqual(model.pendingActionDestination, .aiClassificationSuggestion(fileID: docsFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "ai-category-suggestion")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "AI Category Suggestion")

        model.beginAIClassificationChange(fileID: docsFile.id, targetCategory: "finance/invoices")
        XCTAssertEqual(
            model.pendingActionDestination,
            .changeCategory(
                fileID: docsFile.id,
                initialTargetCategory: "finance/invoices",
                mode: .classifierCorrection
            )
        )

        model.beginDelete()
        XCTAssertEqual(model.pendingActionDestination, .delete(fileID: docsFile.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "delete-file")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Move File to Trash?")
    }

    func testChangeCategoryTargetsComeFromCurrentTreeRows() {
        let docsFile = FileEntrySnapshot.integrationClosureFixture(id: 10, currentName: "a.pdf")
        let rows = RepositoryTreeNodeSnapshot.integrationClosureFixtureTree().sidebarRows

        XCTAssertEqual(
            MainFileActionCategoryOptions.availableCategories(file: docsFile, categoryRows: rows),
            ["docs"]
        )
        XCTAssertEqual(
            MainFileActionCategoryOptions.defaultTargetCategory(for: docsFile, categoryRows: rows),
            "docs"
        )
    }

    @MainActor
    func testWritableActionFileIDUsesSelectionExplicitFileIDAndWriteBlocks() async {
        let first = FileEntrySnapshot.integrationClosureFixture(id: 11, currentName: "first.pdf")
        let second = FileEntrySnapshot.integrationClosureFixture(id: 12, currentName: "second.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(first)]),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        XCTAssertEqual(
            model.selectedWriteActionDisabledMessage(noSelectionMessage: "Select a file first."),
            "Select a file first."
        )

        await model.selectFiles([first.id])

        XCTAssertTrue(model.canPerformWriteAction(fileID: first.id))
        XCTAssertNil(model.writeActionDisabledMessage(fileID: first.id))
        XCTAssertNil(model.selectedWriteActionDisabledMessage(noSelectionMessage: "Select a file first."))
        XCTAssertEqual(model.writableActionFileID(), first.id)
        XCTAssertEqual(model.writableActionFileID(second.id), second.id)

        let readOnlyModel = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [first], isReadOnly: true),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(first)]),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await readOnlyModel.selectFiles([first.id])

        XCTAssertFalse(readOnlyModel.canPerformWriteAction(fileID: first.id))
        XCTAssertEqual(
            readOnlyModel.writeActionDisabledMessage(fileID: first.id),
            MainFileWriteActionDisabledReason.repoReadOnly.message
        )
        XCTAssertEqual(
            readOnlyModel.selectedWriteActionDisabledMessage(noSelectionMessage: "Select a file first."),
            MainFileWriteActionDisabledReason.repoReadOnly.message
        )
        XCTAssertNil(readOnlyModel.writableActionFileID(first.id))
    }

    @MainActor
    func testMultiSelectionHidesSingleFileActionDestinations() async {
        let first = FileEntrySnapshot.integrationClosureFixture(id: 1, currentName: "a.pdf")
        let second = FileEntrySnapshot.integrationClosureFixture(id: 2, currentName: "b.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [first, second]),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationNoopDetailer(),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([first.id, second.id])
        model.beginRename()
        model.beginChangeCategory()
        model.beginDelete()

        XCTAssertNil(model.pendingActionDestination)
    }

    @MainActor
    func testWriteActionsAreDisabledForReadOnlyRepository() async {
        let file = FileEntrySnapshot.integrationClosureFixture(id: 3, currentName: "readonly.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [file], isReadOnly: true),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(file)]),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([file.id])
        model.beginRename()
        model.beginChangeCategory()
        model.beginAIClassificationSuggestion()
        model.beginAIClassificationChange(fileID: file.id, targetCategory: "docs")
        model.beginDelete()

        XCTAssertEqual(model.writeActionDisabledReason(fileID: file.id), .repoReadOnly)
        XCTAssertNil(model.pendingActionDestination)
    }

    @MainActor
    func testWriteActionsAreDisabledWhileListIsLoading() async {
        let file = FileEntrySnapshot.integrationClosureFixture(id: 4, currentName: "loading.pdf")
        let lister = MainListIntegrationSuspendedLister()
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: lister,
            fileDetailer: MainListIntegrationNoopDetailer(),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        let loadingTask = Task {
            await model.loadCurrentCategory("docs")
        }
        await lister.waitForRequest()
        model.beginRename(fileID: file.id)
        await lister.finish()
        await loadingTask.value

        XCTAssertNil(model.pendingActionDestination)
    }

    @MainActor
    func testWriteActionsAreDisabledForImportLockedFile() async {
        let file = FileEntrySnapshot.integrationClosureFixture(id: 8, currentName: "locked.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(
                repoPath: "/tmp/repo",
                files: [file],
                writeLockedFileIDs: [file.id]
            ),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(file)]),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([file.id])
        model.beginAIClassificationSuggestion()
        model.beginDelete()

        XCTAssertEqual(model.writeActionDisabledReason(fileID: file.id), .importLocked)
        XCTAssertEqual(
            model.writeActionDisabledMessage(fileID: file.id),
            MainFileWriteActionDisabledReason.importLocked.message
        )
        XCTAssertNil(model.pendingActionDestination)
    }

    @MainActor
    func testListDbErrorDiagnosticsCollectsCoreSnapshot() async {
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: ".areamatrix/diagnostics/main-list.zip",
            createdAt: 1_700_000_200,
            warnings: []
        )
        let collector = MainListIntegrationDiagnosticsCollector(result: .success(snapshot))
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: []),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationNoopDetailer(),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture()),
            diagnosticsCollector: collector
        )

        await model.collectCurrentListDiagnostics()
        let repoPaths = await collector.recordedRepoPaths()

        XCTAssertEqual(model.diagnosticsState, .collected(snapshot))
        XCTAssertEqual(repoPaths, ["/tmp/repo"])
    }

    @MainActor
    func testExternalRenameKeepsSelectionByFileIDAndRefreshesDetail() async {
        let original = FileEntrySnapshot.integrationClosureFixture(id: 5, currentName: "old.pdf")
        let renamed = FileEntrySnapshot.integrationClosureFixture(id: 5, currentName: "new.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(original)]),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([original.id])
        model.handleExternalRename(renamed)

        XCTAssertEqual(model.selection, .single(original.id))
        XCTAssertEqual(model.files, [renamed])
        XCTAssertEqual(model.selectedFileDetail, renamed)
        XCTAssertEqual(model.statusBanner, .renamedPreservedSelection(fileID: original.id))
    }

    @MainActor
    func testExternalRemovalShowsMissingDetailRecoveryInsteadOfFullRepoError() async {
        let selected = FileEntrySnapshot.integrationClosureFixture(id: 9, currentName: "gone.pdf")
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [selected]),
            fileLister: NoopFileLister(),
            fileDetailer: MainListIntegrationDetailer(results: [.success(selected)]),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        await model.selectFiles([selected.id])
        model.handleExternalRemoval(fileID: selected.id)

        XCTAssertEqual(model.selection, .single(selected.id))
        XCTAssertEqual(model.files, [])
        var missingSelected = selected
        missingSelected.availability = .missing
        XCTAssertEqual(model.selectedFileDetail, missingSelected)
        XCTAssertEqual(model.detailErrorMapping?.kind, .fileNotFound)
        XCTAssertEqual(model.statusBanner, .removedSelectedFile(fileID: selected.id))
    }

    func testStatusDisplayCoversPageSpecStates() {
        XCTAssertEqual(
            FileEntrySnapshot.integrationClosureFixture(
                id: 1,
                currentName: "copied.pdf",
                storageMode: "Copied"
            ).statusDisplay,
            "OK"
        )
        XCTAssertEqual(
            FileEntrySnapshot.integrationClosureFixture(
                id: 2,
                currentName: "indexed.pdf",
                storageMode: "Indexed"
            ).statusDisplay,
            "Index-only"
        )
        XCTAssertEqual(
            FileEntrySnapshot.integrationClosureFixture(
                id: 3,
                currentName: "missing.pdf",
                availability: .missing
            ).statusDisplay,
            "Missing"
        )
        XCTAssertEqual(
            FileEntrySnapshot.integrationClosureFixture(
                id: 4,
                currentName: "placeholder.pdf",
                availability: .iCloudPlaceholder
            ).statusDisplay,
            "iCloud"
        )
    }

    @MainActor
    func testListLoadingExposesCurrentCategoryStatusText() async {
        let file = FileEntrySnapshot.integrationClosureFixture(id: 12, currentName: "loading.pdf")
        let lister = MainListIntegrationSuspendedLister()
        let model = MainFileListModel(
            opening: .integrationClosureFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: lister,
            fileDetailer: MainListIntegrationNoopDetailer(),
            errorMapper: StaticCoreErrorMapper(mapping: .integrationClosureDbFixture())
        )

        let loadingTask = Task { await model.loadCurrentCategory("docs") }
        await lister.waitForRequest()
        XCTAssertEqual(model.loadingStatusText, "正在加载 docs...")
        XCTAssertEqual(model.loadingAccessibilityText, "Loading files. 正在加载 docs...")
        await lister.finish()
        await loadingTask.value
    }
}
