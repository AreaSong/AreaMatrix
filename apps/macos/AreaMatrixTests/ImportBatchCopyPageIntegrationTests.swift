import XCTest
@testable import AreaMatrix

final class ImportBatchCopyPageIntegrationTests: XCTestCase {
    @MainActor
    func testS118BatchCopyImportExposesLastImportedEntryForExistingRefreshFlow() async {
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
            ),
        ]
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)

        XCTAssertEqual(outcome?.succeededEntries.count, 2)
        XCTAssertEqual(outcome?.succeededEntries.last?.currentName, "2026Q1_合同.pdf")
        XCTAssertEqual(outcome?.lastImportedPath, "docs/2026Q1_合同.pdf")
        XCTAssertEqual(model.status, .imported(successful: 2, failed: 0))
    }

    @MainActor
    func testS118BatchCopyImportFailureKeepsProgressAndMappedErrorVisible() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .category("finance"),
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
            ),
        ]
        let importer = S118SequenceBatchImporter(results: [
            .success(.s117Fixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .failure(CoreError.PermissionDenied(path: contractURL.path)),
        ])
        let errorMapper = S117RecordingErrorMapper()
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
    func testS118BatchImportRoutesThroughS120ProgressWithBatchCounts() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            emptyRepositoryOpener: S117StaticRepositoryOpener(opening: opening),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
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
                URL(fileURLWithPath: "/tmp/合同.pdf"),
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
        if case .importProgress(let state) = model.route {
            XCTAssertEqual(state.titleText, "正在导入 2 个文件")
            XCTAssertEqual(state.toolbarText, "Importing 1 / 2")
        } else {
            XCTFail("Expected S1-20 import progress route")
        }
    }

    @MainActor
    func testS118BatchImportFailureKeepsS120ProgressCountsAndMappedError() {
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
            currentPath: "finance/合同.pdf"
        )
        let mapping = CoreErrorMappingSnapshot.s117Error(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(progress)
        model.failImportEntry(progress: progress, mapping: mapping)

        XCTAssertEqual(model.route, .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: "finance/合同.pdf",
            status: .failed(mapping),
            completed: 1,
            failed: 1,
            remaining: 0
        )))
        if case .importProgress(let state) = model.route {
            XCTAssertEqual(state.titleText, "导入已暂停")
            XCTAssertEqual(state.bannerText, "无访问权限")
        } else {
            XCTFail("Expected S1-20 failed import progress route")
        }
    }

    @MainActor
    func testS118BatchImportProgressCanStartBeforeFirstCoreImportCompletes() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
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
            ),
        ]
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"]
        )
        let importer = S118SequenceBatchImporter(results: [
            .success(.s117Fixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .success(.s117Fixture(currentName: "2026Q1_合同.pdf", category: "docs")),
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
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
    func testS118PageIntegrationCoversNameConflictRenameAndReplaceConfirmation() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let request = ImportEntryRequest(
            repoPath: "/tmp/repo",
            source: .dropZone,
            destination: .autoClassify,
            urls: [invoiceURL, contractURL],
            kind: .multipleItems(2),
            availableCategories: ["inbox", "docs", "finance"],
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
            ),
        ]
        let importer = S118SequenceBatchImporter(results: [
            .success(.s117Fixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
            .success(.s117Fixture(currentName: "合同-renamed.pdf", category: "docs")),
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.nameConflictCount, 1)
        XCTAssertEqual(model.rows.map(\.status.tag), ["OK", "NAME"])
        XCTAssertNil(model.importDisabledReason)

        model.renameIncomingFile(for: rows[1].id, to: "合同-renamed.pdf")
        let renamedOutcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        XCTAssertEqual(renamedOutcome?.succeededEntries.count, 2)

        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(recordedRequests.last, S118BatchImportRequest(
            destination: .autoClassify,
            suggestedCategory: "docs",
            overrideFilename: "合同-renamed.pdf",
            duplicateStrategy: .keepBoth
        ))
    }

    @MainActor
    func testS118ReplaceRowsBlockImportUntilS124Confirmation() async {
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
            ),
        ]
        let importer = S118SequenceBatchImporter(results: [
            .success(.s117Fixture(currentName: "Invoice_2026Q1.pdf", category: "finance")),
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .replace)
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")

        guard let context = model.beginReplaceConfirmation(for: rows[0].id) else {
            return XCTFail("Expected S1-24 replace-confirm context")
        }
        model.applyReplaceConfirmation(for: rows[0].id, decision: context.decision(understandsReplace: true))
        XCTAssertNil(model.importDisabledReason)

        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .overwrite
            ),
        ])
    }

    @MainActor
    func testS118TrashUnavailableKeepsNonReplaceDuplicateStrategiesSelectable() async {
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
            ),
        ]
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        XCTAssertEqual(model.replaceOptionVisibility, .disabled)

        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        XCTAssertNil(model.importDisabledReason)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .keepBoth
            ),
        ])
    }

    @MainActor
    func testS118TrashUnavailableRejectsReplaceButKeepsRenameIncomingSelectable() async {
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
            ),
        ]
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
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
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "合同-renamed.pdf",
                duplicateStrategy: .keepBoth
            ),
        ])
    }

}
