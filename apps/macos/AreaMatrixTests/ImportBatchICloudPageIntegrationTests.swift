@testable import AreaMatrix
import SwiftUI
import XCTest

final class ImportBatchICloudPageIntegrationTests: XCTestCase {
    func testBatchAddTagsPageIntegrationAllowsReadOnlyEntryButBlocksApply() {
        let disabledReason = MainFileWriteActionDisabledReason.repoReadOnly.message
        let help = BatchAddTagsEntryPolicy.openHelp(disabledReason: disabledReason)
        let pending = BatchTagValidation.pendingStateAfterAdding(
            input: "urgent",
            pendingTags: [],
            catalog: .batchAddTagsTagCatalogFixture(fileID: 31),
            disabledReason: disabledReason
        )

        XCTAssertEqual(
            help,
            "Repository is read-only. You can still review selected files and tag candidates."
        )
        XCTAssertEqual(pending.fieldError, "Tag store is read-only.")
        XCTAssertFalse(BatchTagValidation.canApply(BatchTagApplyEligibility(
            isApplying: false,
            disabledReason: disabledReason,
            input: "",
            pendingTags: ["urgent"],
            fieldError: nil,
            selectedCount: 2
        )))
    }

    func testBatchAddTagsPageIntegrationBuildsListAndCommandPaletteRoutesForSameSheet() {
        let first = FileEntrySnapshot.batchAddTagsRouteFixture(id: 1, currentName: "a.pdf")
        let second = FileEntrySnapshot.batchAddTagsRouteFixture(id: 2, currentName: "b.pdf")
        let route = BatchAddTagsRoute(
            source: .listContextMenu,
            fileIDs: [first.id, second.id],
            selectedCount: 2,
            disabledReason: MainFileBatchEntryPolicy.disabledReason(
                selectedFiles: [first, second],
                isReadOnly: false,
                isLoading: false,
                writeLockedFileIDs: []
            )
        )
        let commandRoute = BatchAddTagsRoute(
            source: .commandPalette,
            fileIDs: route.fileIDs,
            selectedCount: route.selectedCount,
            disabledReason: route.disabledReason
        )

        XCTAssertEqual(route.fileIDs, [1, 2])
        XCTAssertEqual(route.selectedCount, 2)
        XCTAssertNil(route.disabledReason)
        XCTAssertEqual(commandRoute.fileIDs, route.fileIDs)
        XCTAssertEqual(commandRoute.selectedCount, route.selectedCount)
    }

    func testBatchAddTagsCommandPaletteRouteExposesContextualAddTagsCommand() {
        var commandQuery = "tag"
        assertTestMirrorDescription(of: SearchCommandPaletteRouteView(
            query: Binding(get: { commandQuery }, set: { commandQuery = $0 }),
            state: .idle,
            onLoad: {},
            onExecuteTarget: { _ in },
            onClose: {}
        ).body, contains: [
            "command-palette-search-route",
            "CommandPaletteView"
        ])
    }

    @MainActor
    func testImportBatchICloudPendingRowsDoNotSilentlyImportUnavailableRows() async {
        let localURL = importBatchInvoiceURL()
        let cloudURL = importBatchICloudPlaceholderURL()
        let request = importBatchBatchRequest(urls: [localURL, cloudURL])
        let rows = [
            importBatchReadyBatchRow(url: localURL),
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: cloudURL,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        ]
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.iCloudPlaceholderCount, 1)
        XCTAssertNil(model.importDisabledReason)

        model.markICloudPlaceholderPending(rowID: rows[1].id)
        XCTAssertNil(model.importDisabledReason)

        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.succeededEntries.first?.storageMode, "Copied")
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), importBatchProgress(
            completed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/Invoice_2026Q1.pdf",
            pending: 1,
            items: [
                importBatchProgressItem(
                    fileID: 42,
                    sourcePath: importBatchSourcePath(),
                    targetPath: "finance/Invoice_2026Q1.pdf",
                    phase: .done
                )
            ]
        ))
        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
    }

    @MainActor
    func testImportBatchAllICloudPendingStillBlocksImport() {
        let cloudURLs = [
            importBatchICloudPlaceholderURL(variant: "A"),
            importBatchICloudPlaceholderURL(variant: "B")
        ]
        let request = ImportEntryRequest(
            repoPath: importBatchRepoPath(),
            source: .dropZone,
            destination: .autoClassify,
            urls: cloudURLs,
            kind: .multipleItems(2),
            availableCategories: ["inbox", "finance"]
        )
        let rows = cloudURLs.map { url in
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: url,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        }
        let model = ImportBatchCopyImportModel(
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)

        XCTAssertEqual(model.iCloudPlaceholderCount, 2)
        XCTAssertEqual(model.importDisabledReason, "没有可导入的批量项目")
    }
}
