@testable import AreaMatrix
import XCTest

final class ImportFolderPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testImportFolderEntryCancelAndImportRoutesThroughImportProgressProgressAndResult() async throws {
        let folderURL = try makeImportFolderTemporaryDirectory()
        defer { removeTestTemporaryItems(folderURL) }
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let announcer = RecordingAccessibilityAnnouncer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: ImportSingleFileStaticRepositoryOpener(opening: opening),
            accessibilityAnnouncer: announcer,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [folderURL],
            destination: .category("finance")
        )
        XCTAssertEqual(model.pendingImportEntry?.kind, .folder)
        XCTAssertEqual(model.pendingImportEntry?.destination, .category("finance"))

        model.dismissImportEntry()
        XCTAssertNil(model.pendingImportEntry)

        model.startImportEntry(opening: opening, source: .dropZone, urls: [folderURL])
        model.updateImportEntryProgress(importBatchProgress(
            completed: 0,
            total: 2,
            currentPath: "finance/invoice.pdf"
        ))

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: "finance/invoice.pdf",
            status: .running,
            completed: 0,
            failed: 0,
            remaining: 2
        )))

        await model.finishImportEntry(
            repoPath: opening.config.repoPath,
            entry: .importSingleFileFixture(currentName: "invoice.pdf", category: "finance")
        )

        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：invoice.pdf")
        XCTAssertEqual(announcer.announcements, ["已导入：invoice.pdf"])
    }

    @MainActor
    func testImportFolderIntegrationUsesClassifyCopyAndIndexWithoutOutOfScopeCalls(
    ) async {
        let copyURL = URL(fileURLWithPath: "/tmp/client-a/invoice.pdf")
        let indexURL = URL(fileURLWithPath: "/tmp/client-a/reference.pdf")
        let scanner = importFolderStaticScanner(urls: [copyURL, indexURL])
        let predictor = ImportFolderMappedPredictor(resultsByFilename: [
            "invoice.pdf": .success(.importFolderPrediction(category: "finance", suggestedName: "invoice-2026.pdf")),
            "reference.pdf": .success(.importFolderPrediction(category: "docs", suggestedName: "reference-index.pdf"))
        ])
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: scanner
        )
        let request = importFolderFolderRequest(
            rootURL: URL(fileURLWithPath: "/tmp/client-a"),
            destination: .category("docs")
        )

        await model.load(request: request)
        XCTAssertEqual(model.selectedDestination, .category("docs"))
        XCTAssertEqual(model.targetRelativePath(for: model.rows[0]), "docs/invoice-2026.pdf")

        _ = await model.importReadyFiles()
        await model.load(request: request)
        model.selectedStorageMode = .indexOnly
        _ = await model.importReadyFiles()

        let predictRequests = await predictor.recordedRequests()
        let importRequests = await importer.recordedRequests()

        XCTAssertEqual(Set(predictRequests.map(\.filename)), ["invoice.pdf", "reference.pdf"])
        XCTAssertEqual(importRequests, importFolderExpectedCopyAndIndexRequests())
    }

    @MainActor
    func testImportFolderScanErrorsAndICloudPlaceholdersBlockOrSummarizeWithoutSilentImport() async {
        let readyURL = URL(fileURLWithPath: "/tmp/client-a/ready.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/client-a/cloud.pdf.icloud")
        let scanner = importFolderScanErrorScanner(readyURL: readyURL, cloudURL: cloudURL)
        let predictor = ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction())])
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        XCTAssertEqual(model.importDisabledReason, "预扫描存在错误，请先 Retry scan 或 Cancel")
        let blockedOutcome = await model.importReadyFiles()
        let blockedRequests = await importer.recordedRequests()
        XCTAssertNil(blockedOutcome)
        XCTAssertEqual(blockedRequests, [])

        let cleanScanner = importFolderCleanPlaceholderScanner(readyURL: readyURL, cloudURL: cloudURL)
        let cleanModel = ImportFolderPreviewModel(
            predictor: ImportFolderRecordingPredictor(results: [.success(.importFolderPrediction())]),
            importer: ImportBatchRecordingBatchImporter(),
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: cleanScanner
        )

        await cleanModel.load(request: importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        let outcome = await cleanModel.importReadyFiles()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "folder summary"), importBatchProgress(
            completed: 1,
            total: 2,
            remaining: 0,
            currentPath: "docs/ready.pdf",
            pending: 1,
            items: [
                importBatchProgressItem(
                    fileID: 42,
                    sourcePath: "/tmp/source.pdf",
                    targetPath: "docs/ready.pdf",
                    phase: .done
                )
            ]
        ))
    }
}

private func importFolderExpectedCopyAndIndexRequests() -> [ImportBatchBatchImportRequest] {
    [
        importFolderExpectedImportRequest(storageMode: .copy, overrideFilename: "invoice-2026.pdf"),
        importFolderExpectedImportRequest(storageMode: .copy, overrideFilename: "reference-index.pdf"),
        importFolderExpectedImportRequest(storageMode: .indexOnly, overrideFilename: "invoice-2026.pdf"),
        importFolderExpectedImportRequest(storageMode: .indexOnly, overrideFilename: "reference-index.pdf")
    ]
}

private func importFolderExpectedImportRequest(
    storageMode: ImportSingleFileStorageMode,
    overrideFilename: String
) -> ImportBatchBatchImportRequest {
    ImportBatchBatchImportRequest(
        storageMode: storageMode,
        destination: .category("docs"),
        suggestedCategory: "docs",
        overrideFilename: overrideFilename,
        duplicateStrategy: .ask
    )
}
