@testable import AreaMatrix
import XCTest

final class ImportBatchICloudPageIntegrationTests: XCTestCase {
    func testS209PageIntegrationAllowsReadOnlyEntryButBlocksApply() {
        let disabledReason = MainFileWriteActionDisabledReason.repoReadOnly.rawValue
        let help = BatchAddTagsEntryPolicy.openHelp(disabledReason: disabledReason)
        let pending = BatchTagValidation.pendingStateAfterAdding(
            input: "urgent",
            pendingTags: [],
            catalog: .s209TagCatalogFixture(fileID: 31),
            disabledReason: disabledReason
        )

        XCTAssertEqual(
            help,
            "Repository is read-only. You can still review selected files and tag candidates."
        )
        XCTAssertEqual(pending.fieldError, "Tag store is read-only.")
        XCTAssertFalse(BatchTagValidation.canApply(
            isApplying: false,
            disabledReason: disabledReason,
            input: "",
            pendingTags: ["urgent"],
            fieldError: nil,
            selectedCount: 2
        ))
    }

    func testS209PageIntegrationBuildsListAndCommandPaletteRoutesForSameSheet() {
        let first = FileEntrySnapshot.s209RouteFixture(id: 1, currentName: "a.pdf")
        let second = FileEntrySnapshot.s209RouteFixture(id: 2, currentName: "b.pdf")
        let route = BatchAddTagsRoute(
            source: .listContextMenu,
            fileIDs: [first.id, second.id],
            selectedCount: 2,
            disabledReason: BatchAddTagsEntryPolicy.disabledReason(
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

    func testS209CommandPaletteRouteExposesContextualAddTagsCommand() {
        let route = BatchAddTagsRoute(source: .commandPalette, fileIDs: [1, 2], selectedCount: 2, disabledReason: nil)
        let body = s209RouteMirrorDescription(of: SearchCommandPaletteRouteView(
            query: "tag",
            batchAddTagsRoute: route,
            onOpenBatchAddTags: { _ in },
            onClose: {}
        ).body)

        XCTAssertTrue(body.contains("S2-15-search-route"))
        XCTAssertTrue(body.contains("S2-09-command-palette-add-tags"))
        XCTAssertTrue(body.contains("Add tags..."))
    }

    @MainActor
    func testS118ICloudPendingRowsDoNotSilentlyImportUnavailableRows() async {
        let localURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/iCloudOnly.pdf.icloud")
        let request = s118BatchRequest(urls: [localURL, cloudURL])
        let rows = [
            s118ReadyBatchRow(url: localURL),
            ImportBatchPreviewRow.iCloudPlaceholder(
                url: cloudURL,
                message: "iCloud placeholder 需要下载后才能导入"
            )
        ]
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
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
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "Import ready only"), ImportBatchProgressSnapshot(
            completed: 1,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "finance/Invoice_2026Q1.pdf",
            skipped: 0,
            pending: 1
        ))
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
    }

    @MainActor
    func testS118AllICloudPendingStillBlocksImport() {
        let cloudURLs = [
            URL(fileURLWithPath: "/tmp/iCloudOnlyA.pdf.icloud"),
            URL(fileURLWithPath: "/tmp/iCloudOnlyB.pdf.icloud")
        ]
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
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
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)

        XCTAssertEqual(model.iCloudPlaceholderCount, 2)
        XCTAssertEqual(model.importDisabledReason, "没有可导入的批量项目")
    }
}

extension MainRepositoryDetailPaneTagActions {
    static var noop: MainRepositoryDetailPaneTagActions {
        MainRepositoryDetailPaneTagActions(
            onLoadTags: {},
            onRetryTags: {},
            onAddTag: { _ in },
            onRemoveTag: { _ in },
            onUndoTagChange: {},
            onDismissTagUndoToast: {},
            onBatchTagUndoStateChange: { _ in }
        )
    }
}

private extension FileEntrySnapshot {
    static func s209RouteFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "s209-route-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

private func s209RouteMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS209RouteMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS209RouteMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        if let label = child.label {
            lines.append(label)
        }
        appendS209RouteMirrorDescription(of: child.value, to: &lines)
    }
}
