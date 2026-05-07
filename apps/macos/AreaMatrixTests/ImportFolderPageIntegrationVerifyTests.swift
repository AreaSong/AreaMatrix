import XCTest
@testable import AreaMatrix

final class ImportFolderPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS119EntryCancelAndImportRoutesThroughS120ProgressAndResult() async throws {
        let folderURL = try makeImportFolderTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let announcer = S117RecordingAccessibilityAnnouncer()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: S117StaticRepositoryOpener(opening: opening),
            accessibilityAnnouncer: announcer,
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.startImportEntry(opening: opening, source: .dropZone, urls: [folderURL], destination: .category("finance"))
        XCTAssertEqual(model.pendingImportEntry?.kind, .folder)
        XCTAssertEqual(model.pendingImportEntry?.destination, .category("finance"))

        model.dismissImportEntry()
        XCTAssertNil(model.pendingImportEntry)

        model.startImportEntry(opening: opening, source: .dropZone, urls: [folderURL])
        model.updateImportEntryProgress(ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: 2,
            remaining: 2,
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
            entry: .s117Fixture(currentName: "invoice.pdf", category: "finance")
        )

        XCTAssertEqual(model.route, .mainEmpty(opening))
        XCTAssertEqual(model.toastMessage, "已导入：invoice.pdf")
        XCTAssertEqual(announcer.announcements, ["已导入：invoice.pdf"])
    }

    @MainActor
    func testS119PageIntegrationUsesC105C106AndC108WithoutControlMapOutOfScopeCalls() async {
        let copyURL = URL(fileURLWithPath: "/tmp/client-a/invoice.pdf")
        let indexURL = URL(fileURLWithPath: "/tmp/client-a/reference.pdf")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [
                ImportFolderPreviewRow.loading(fileURL: copyURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
                ImportFolderPreviewRow.loading(fileURL: indexURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
            ],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119MappedPredictor(resultsByFilename: [
            "invoice.pdf": .success(.s119Prediction(category: "finance", suggestedName: "invoice-2026.pdf")),
            "reference.pdf": .success(.s119Prediction(category: "docs", suggestedName: "reference-index.pdf")),
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )
        let request = s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a"), destination: .category("docs"))

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
        XCTAssertEqual(importRequests, [
            S118BatchImportRequest(
                storageMode: .copy,
                destination: .category("docs"),
                suggestedCategory: "docs",
                overrideFilename: "invoice-2026.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                storageMode: .copy,
                destination: .category("docs"),
                suggestedCategory: "docs",
                overrideFilename: "reference-index.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                storageMode: .indexOnly,
                destination: .category("docs"),
                suggestedCategory: "docs",
                overrideFilename: "invoice-2026.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                storageMode: .indexOnly,
                destination: .category("docs"),
                suggestedCategory: "docs",
                overrideFilename: "reference-index.pdf",
                duplicateStrategy: .ask
            ),
        ])
    }

    @MainActor
    func testS119ScanErrorsAndICloudPlaceholdersBlockOrSummarizeWithoutSilentImport() async {
        let readyURL = URL(fileURLWithPath: "/tmp/client-a/ready.pdf")
        let cloudURL = URL(fileURLWithPath: "/tmp/client-a/cloud.pdf.icloud")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [
                ImportFolderPreviewRow.loading(fileURL: readyURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
                ImportFolderPreviewRow.loading(fileURL: cloudURL, rootURL: URL(fileURLWithPath: "/tmp/client-a"))
                    .withStatus(.iCloudPlaceholder(path: cloudURL.path)),
            ],
            folderCount: 0,
            skippedRules: [],
            errors: [ImportFolderScanError(path: "/tmp/client-a/private", message: "Permission denied")]
        ))
        let predictor = S119RecordingPredictor(results: [.success(.s119Prediction())])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner
        )

        await model.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        XCTAssertEqual(model.importDisabledReason, "预扫描存在错误，请先 Retry scan 或 Cancel")
        let blockedOutcome = await model.importReadyFiles()
        let blockedRequests = await importer.recordedRequests()
        XCTAssertNil(blockedOutcome)
        XCTAssertEqual(blockedRequests, [])

        let cleanScanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [
                ImportFolderPreviewRow.loading(fileURL: readyURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
                ImportFolderPreviewRow.loading(fileURL: cloudURL, rootURL: URL(fileURLWithPath: "/tmp/client-a"))
                    .withStatus(.iCloudPlaceholder(path: cloudURL.path)),
            ],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let cleanModel = ImportFolderPreviewModel(
            predictor: S119RecordingPredictor(results: [.success(.s119Prediction())]),
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: cleanScanner
        )

        await cleanModel.load(request: s119FolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        let outcome = await cleanModel.importReadyFiles()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingICloudCount, 1)
        XCTAssertTrue(outcome?.needsResultSummary == true)
        XCTAssertEqual(outcome?.progressSnapshot(currentPath: "folder summary"), ImportBatchProgressSnapshot(
            completed: 1,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "docs/ready.pdf",
            skipped: 0,
            pending: 1
        ))
    }

    @MainActor
    func testS119PageIntegrationConflictReviewCoversDupNameBlockedAndReplaceConfirmation() async throws {
        let duplicateURL = URL(fileURLWithPath: "/tmp/client-a/dup.pdf")
        let nameURL = URL(fileURLWithPath: "/tmp/client-a/name.pdf")
        let blockedURL = URL(fileURLWithPath: "/tmp/client-a/private.pdf")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [
                ImportFolderPreviewRow.loading(fileURL: duplicateURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
                ImportFolderPreviewRow.loading(fileURL: nameURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
                ImportFolderPreviewRow.loading(fileURL: blockedURL, rootURL: URL(fileURLWithPath: "/tmp/client-a")),
            ],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let predictor = S119MappedPredictor(resultsByFilename: [
            "dup.pdf": .success(.s119Prediction(category: "docs", suggestedName: "dup.pdf")),
            "name.pdf": .success(.s119Prediction(category: "docs", suggestedName: "name.pdf")),
            "private.pdf": .success(.s119Prediction(category: "docs", suggestedName: "private.pdf")),
        ])
        let prechecker = S119StaticConflictPrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf"),
            nameURL.path: .nameConflict(existingPath: "docs/name.pdf"),
            blockedURL.path: .blocked("Conflict precheck failed: permission denied"),
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: prechecker,
            scanner: scanner
        )
        let request = s119FolderRequest(
            rootURL: URL(fileURLWithPath: "/tmp/client-a"),
            allowReplaceDuringImport: true
        )

        await model.load(request: request)

        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "NAME", "BLOCKED"])
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        let initialRequests = await importer.recordedRequests()
        XCTAssertEqual(initialRequests, [])

        model.setRowStatus(.skippedDuplicate(existingPath: "docs/existing-dup.pdf"), for: duplicateURL.path)
        model.updateNameConflictResolution(for: nameURL.path, resolution: .replace(isConfirmed: false))
        model.setRowStatus(.nameConflict(
            existingPath: "docs/name.pdf",
            resolution: .replace(isConfirmed: false)
        ), for: blockedURL.path)

        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        let nameContext: ImportSingleFileReplaceConfirmationContext = try XCTUnwrap(
            model.beginReplaceConfirmation(for: nameURL.path)
        )
        model.applyReplaceConfirmation(for: nameURL.path, decision: nameContext.decision(understandsReplace: true))
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")

        let blockedContext: ImportSingleFileReplaceConfirmationContext = try XCTUnwrap(
            model.beginReplaceConfirmation(for: blockedURL.path)
        )
        model.applyReplaceConfirmation(for: blockedURL.path, decision: blockedContext.decision(understandsReplace: true))
        let outcome = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "name.pdf",
                duplicateStrategy: .overwrite
            ),
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "private.pdf",
                duplicateStrategy: .overwrite
            ),
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 2)
        XCTAssertEqual(outcome?.skippedDuplicateCount, 1)
        XCTAssertEqual(model.rows.map(\.status.tag), ["SKIPPED", "IMPORTED", "IMPORTED"])
    }

    @MainActor
    func testS119ICloudDownloadRetryPreservesStorageModeAndDestination() async {
        let cloudURL = URL(fileURLWithPath: "/tmp/client-a/cloud.pdf.icloud")
        let scanner = S119SequenceFolderScanner(results: [
            ImportFolderScanResult(
                rows: [
                    ImportFolderPreviewRow.loading(fileURL: cloudURL, rootURL: URL(fileURLWithPath: "/tmp/client-a"))
                        .withStatus(.iCloudPlaceholder(path: cloudURL.path)),
                ],
                folderCount: 0,
                skippedRules: [],
                errors: []
            ),
            ImportFolderScanResult(
                rows: [
                    ImportFolderPreviewRow.loading(
                        fileURL: URL(fileURLWithPath: "/tmp/client-a/cloud.pdf"),
                        rootURL: URL(fileURLWithPath: "/tmp/client-a")
                    ),
                ],
                folderCount: 0,
                skippedRules: [],
                errors: []
            ),
        ])
        let downloader = S119RecordingICloudDownloader()
        let model = ImportFolderPreviewModel(
            predictor: S119RecordingPredictor(results: [.success(.s119Prediction())]),
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: S119NoopConflictPrechecker(),
            scanner: scanner,
            placeholderDownloader: downloader
        )

        await model.load(request: s119FolderRequest(
            rootURL: URL(fileURLWithPath: "/tmp/client-a"),
            destination: .category("finance")
        ))
        model.selectedStorageMode = .indexOnly
        model.selectedDestination = .category("docs")

        let didRetry = await model.downloadICloudPlaceholdersAndRetry()
        let downloadedURLs = await downloader.recordedURLs()

        XCTAssertTrue(didRetry)
        XCTAssertEqual(downloadedURLs, [cloudURL])
        XCTAssertEqual(model.selectedStorageMode, .indexOnly)
        XCTAssertEqual(model.selectedDestination, .category("docs"))
        XCTAssertEqual(model.rows.map(\.status.tag), ["OK"])
    }

    @MainActor
    func testS119FailedImportRemainsOnProgressWithMappedError() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let progress = ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "docs/private.pdf"
        )
        let mapping = CoreErrorMappingSnapshot.s117Error(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(progress)
        model.failImportEntry(progress: progress, mapping: mapping)

        XCTAssertEqual(model.route, .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: "docs/private.pdf",
            status: .failed(mapping),
            completed: 1,
            failed: 1,
            remaining: 0
        )))
    }
}
