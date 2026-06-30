@testable import AreaMatrix
import XCTest

final class ImportBatchCopyPageIntegrationTests: XCTestCase {
    @MainActor
    func testImportBatchBatchCopyImportExposesLastImportedEntryForExistingRefreshFlow() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"]
        )
        let rows = [
            ImportBatchPreviewRow.ready(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            ),
            ImportBatchPreviewRow.ready(
                url: contractURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "2026Q1_合同.pdf",
                    reason: .keyword,
                    confidence: 0.82
                )
            )
        ]
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries.count, 2)
        XCTAssertEqual(outcome?.succeededEntries.last?.currentName, "2026Q1_合同.pdf")
        XCTAssertEqual(outcome?.lastImportedPath, "docs/2026Q1_合同.pdf")
        XCTAssertEqual(model.status, .imported(successful: 2, failed: 0))
    }

    @MainActor
    func testImportBatchBatchCopyImportFailureKeepsProgressAndMappedErrorVisible() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = importBatchBatchRequest(
            destination: .category("finance"),
            urls: [invoiceURL, contractURL]
        )
        let rows = importBatchReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .failure(CoreError.PermissionDenied(path: contractURL.path))
        ])
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: errorMapper
        )
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        model.applyPreviewRows(rows, request: request, selectedDestination: .category("finance"))
        let outcome = await model.importReadyFiles(selectedDestination: .category("finance")) { progress in
            progressSnapshots.append(progress)
        }

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.failedCount, 1)
        XCTAssertEqual(outcome?.lastImportedPath, "finance/Invoice_2026Q1.pdf")
        XCTAssertEqual(model.lastFailureMapping?.userMessage, "无访问权限")
        XCTAssertEqual(progressSnapshots.last, ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/2026Q1_合同.pdf"
        ))
    }

    @MainActor
    func testImportBatchBatchImportRoutesThroughImportProgressProgressWithBatchCounts() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: ImportSingleFileStaticRepositoryOpener(opening: opening),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let progress = ImportBatchProgressSnapshot(
            completed: 1,
            failed: 0,
            total: 2,
            remaining: 1,
            currentPath: "docs/合同.pdf"
        )

        model.route = .mainList(opening)
        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [
                URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf"),
                URL(fileURLWithPath: "/tmp/合同.pdf")
            ]
        )
        model.updateImportEntryProgress(progress)

        XCTAssertNil(model.pendingImportEntry)
        XCTAssertEqual(model.route, .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: "docs/合同.pdf",
            status: .running,
            completed: 1,
            failed: 0,
            remaining: 1
        )))
        if case let .importProgress(state) = model.route {
            XCTAssertEqual(state.titleText, "正在导入 2 个文件")
            XCTAssertEqual(state.toolbarText, "Importing 1 / 2")
        } else {
            XCTFail("Expected import-progress import progress route")
        }
    }

    @MainActor
    func testImportBatchBatchImportFailureRoutesToImportResultResultInsteadOfFatalPause() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let progress = ImportBatchProgressSnapshot(
            completed: 1,
            failed: 1,
            total: 2,
            remaining: 0,
            currentPath: "finance/合同.pdf"
        )
        let mapping = CoreErrorMappingSnapshot.importSingleFileError(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(progress)
        model.failImportEntry(progress: progress, mapping: mapping)

        if case let .importResult(result) = model.route {
            XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
            XCTAssertEqual(result.items.map(\.status), [.failed])
        } else {
            XCTFail("Expected import-result import result route")
        }
    }

    @MainActor
    func testImportProgressViewDetailsRoutesToImportResultImportResult() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )
        let progress = ImportBatchProgressSnapshot(
            completed: 1,
            failed: 0,
            total: 2,
            remaining: 1,
            currentPath: "finance/合同.pdf"
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(progress)
        model.viewImportProgressDetails()

        if case let .importResult(result) = model.route {
            XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 0, stopped 0, pending 1.")
            XCTAssertEqual(result.currentPath, "finance/合同.pdf")
        } else {
            XCTFail("Expected import-result import result route")
        }
    }
}

final class ImportBatchCopyProgressIntegrationTests: XCTestCase {
    @MainActor
    func testImportBatchBatchImportProgressCanStartBeforeFirstCoreImportCompletes() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let rows = importBatchReadyBatchRows(invoiceURL: invoiceURL, contractURL: contractURL)
        let request = importBatchBatchRequest(urls: [invoiceURL, contractURL])
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .success(.importSingleFileFixture(currentName: "2026Q1_合同.pdf", category: "docs"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let initialProgress = ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: model.importableRows.count,
            remaining: model.importableRows.count,
            currentPath: model.currentImportPath ?? request.sheetTitle
        )
        progressSnapshots.append(initialProgress)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify) { progress in
            progressSnapshots.append(progress)
        }

        XCTAssertEqual(progressSnapshots.first, ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: 2,
            remaining: 2,
            currentPath: "finance/Invoice_2026Q1.pdf"
        ))
        XCTAssertEqual(progressSnapshots.last, ImportBatchProgressSnapshot(
            completed: 2,
            failed: 0,
            total: 2,
            remaining: 0,
            currentPath: "docs/2026Q1_合同.pdf"
        ))
    }

    @MainActor
    func testImportBatchPageIntegrationCoversNameConflictRenameAndReplaceConfirmation() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = importBatchBatchRequest(
            urls: [invoiceURL, contractURL],
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        )
        let rows = [
            ImportBatchPreviewRow.ready(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            ),
            ImportBatchPreviewRow.nameConflict(
                url: contractURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "合同.pdf",
                    reason: .keyword,
                    confidence: 0.82
                ),
                existingPath: "docs/合同.pdf"
            )
        ]
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .success(.importSingleFileFixture(currentName: "合同-renamed.pdf", category: "docs"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.nameConflictCount, 1)
        XCTAssertEqual(model.rows.map(\.status.tag), ["OK", "NAME"])
        XCTAssertNil(model.importDisabledReason)

        model.renameIncomingFile(for: rows[1].id, to: "合同-renamed.pdf")
        let renamedOutcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        XCTAssertEqual(renamedOutcome?.succeededEntries.count, 2)

        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(recordedRequests.last, ImportBatchBatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "合同-renamed.pdf",
            duplicateStrategy: .keepBoth
        ))
    }

    @MainActor
    func testImportBatchReplaceRowsBlockImportUntilReplaceConfirmConfirmation() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL],
            kind: .multipleItems(1),
            availableCategories: ["inbox", "finance"],
            allowReplaceDuringImport: true,
            isTrashAvailable: true
        )
        let rows = [
            ImportBatchPreviewRow.duplicate(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                ),
                existingPath: "finance/Invoice_2026Q1.pdf"
            )
        ]
        let importer = ImportBatchSequenceBatchImporter(results: [
            .success(.importSingleFileFixture(currentName: "Invoice_2026Q1.pdf", category: "finance"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .replace)
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")

        guard let context = model.beginReplaceConfirmation(for: rows[0].id) else {
            return XCTFail("Expected replace-confirm replace-confirm context")
        }
        model.applyReplaceConfirmation(for: rows[0].id, decision: context.decision(understandsReplace: true))
        XCTAssertNil(model.importDisabledReason)

        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .overwrite
            )
        ])
    }

    @MainActor
    func testImportBatchTrashUnavailableKeepsNonReplaceDuplicateStrategiesSelectable() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL],
            kind: .multipleItems(1),
            availableCategories: ["inbox", "finance"],
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        )
        let rows = [
            ImportBatchPreviewRow.duplicate(
                url: invoiceURL,
                prediction: ClassifyResultSnapshot(
                    category: "finance",
                    suggestedName: "Invoice_2026Q1.pdf",
                    reason: .keyword,
                    confidence: 0.9
                ),
                existingPath: "finance/Invoice_2026Q1.pdf"
            )
        ]
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.replaceOptionVisibility, .disabled)

        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        XCTAssertNil(model.importDisabledReason)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .keepBoth
            )
        ])
    }

    @MainActor
    func testImportBatchTrashUnavailableRejectsReplaceButKeepsRenameIncomingSelectable() async {
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [contractURL],
            kind: .multipleItems(1),
            availableCategories: ["inbox", "docs"],
            allowReplaceDuringImport: true,
            isTrashAvailable: false
        )
        let rows = [
            ImportBatchPreviewRow.nameConflict(
                url: contractURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "合同.pdf",
                    reason: .keyword,
                    confidence: 0.82
                ),
                existingPath: "docs/合同.pdf"
            )
        ]
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.updateNameConflictResolution(for: rows[0].id, resolution: .replace(isConfirmed: false))
        XCTAssertEqual(model.rows.first?.nameConflictResolution, .keepBoth)

        model.renameIncomingFile(for: rows[0].id, to: "合同-renamed.pdf")
        XCTAssertNil(model.importDisabledReason)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "合同-renamed.pdf",
                duplicateStrategy: .keepBoth
            )
        ])
    }
}
