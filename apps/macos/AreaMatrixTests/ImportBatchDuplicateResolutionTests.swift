@testable import AreaMatrix
import XCTest

final class ImportBatchDuplicateResolutionTests: XCTestCase {
    @MainActor
    func testDuplicateFileErrorFromCoreImportBecomesVisibleConflictAndStopsBatch() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.s117Fixture(currentName: "2026Q1_合同.pdf", category: "docs"))
        ])
        let errorMapper = S117RecordingErrorMapper()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: errorMapper
        )
        let rows = [
            s118PreviewRow(url: invoiceURL, category: "finance", suggestedName: "Invoice_2026Q1.pdf"),
            s118PreviewRow(url: contractURL, category: "docs", suggestedName: "2026Q1_合同.pdf")
        ]
        let request = s118BatchRequest(urls: [invoiceURL, contractURL])
        var progressSnapshots: [ImportBatchProgressSnapshot] = []

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify) { progress in
            progressSnapshots.append(progress)
        }
        let recordedRequests = await importer.recordedRequests()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            )
        ])
        XCTAssertEqual(mappedErrors, [])
        XCTAssertEqual(outcome?.succeededEntries.count, 0)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.total, 2)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 1)
        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "OK"])
        XCTAssertEqual(model.rows.first?.status.detail, "Skip: finance/existing-invoice.pdf")
        XCTAssertEqual(model.status, .idle)
        XCTAssertEqual(progressSnapshots.last, ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: 2,
            remaining: 2,
            currentPath: "finance/Invoice_2026Q1.pdf"
        ))
    }

    @MainActor
    func testCoreDetectedDuplicateSurvivesPreviewReapplyAndCanRetryKeepBoth() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.s117Fixture(currentName: "Invoice_2026Q1 2.pdf", category: "finance"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )
        let rows = [s118PreviewRow(url: invoiceURL, category: "finance", suggestedName: "Invoice_2026Q1.pdf")]
        let request = s118BatchRequest(urls: [invoiceURL])

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .keepBoth
            )
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 0)
        XCTAssertEqual(model.rows.map(\.status.tag), ["IMPORTED"])
    }

    @MainActor
    func testCoreDetectedDuplicateDefaultsToSkipAfterUserRetriesImport() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let contractURL = URL(fileURLWithPath: "/tmp/合同.pdf")
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.s117Fixture(currentName: "2026Q1_合同.pdf", category: "docs"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )
        let rows = [
            s118PreviewRow(url: invoiceURL, category: "finance", suggestedName: "Invoice_2026Q1.pdf"),
            s118PreviewRow(url: contractURL, category: "docs", suggestedName: "2026Q1_合同.pdf")
        ]
        let request = s118BatchRequest(urls: [invoiceURL, contractURL])

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "2026Q1_合同.pdf",
                duplicateStrategy: .ask
            )
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.total, 1)
        XCTAssertEqual(outcome?.failedCount, 0)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 0)
        XCTAssertEqual(model.skippedDuplicateCount, 1)
        XCTAssertEqual(model.rows.map(\.status.tag), ["SKIPPED", "IMPORTED"])
        XCTAssertEqual(model.rows.first?.status.detail, "Duplicate skipped: finance/existing-invoice.pdf")
    }

    @MainActor
    func testCoreDetectedDuplicateCanImportKeepBothThroughCoreDuplicateStrategy() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.s117Fixture(currentName: "Invoice_2026Q1 2.pdf", category: "finance"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )
        let rows = [s118PreviewRow(url: invoiceURL, category: "finance", suggestedName: "Invoice_2026Q1.pdf")]
        let request = s118BatchRequest(urls: [invoiceURL])

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .keepBoth
            )
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 0)
        XCTAssertEqual(model.rows.map(\.status.tag), ["IMPORTED"])
    }

    @MainActor
    func testShowExistingFileRevealsDuplicatePathFromPendingBatchRequest() {
        let revealer = S118RecordingFileRevealer()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            fileRevealer: revealer,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [
                URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf"),
                URL(fileURLWithPath: "/tmp/合同.pdf")
            ]
        )
        model.showImportEntryExistingFile(relativePath: "finance/existing-invoice.pdf")

        XCTAssertEqual(revealer.requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(revealer.requests.map(\.relativePath), ["finance/existing-invoice.pdf"])
        XCTAssertNil(model.toastMessage)
    }

    @MainActor
    func testShowExistingFileFailureReportsActionError() {
        let revealer = S118RecordingFileRevealer(result: .failure(RepositoryFileActionError.fileMissing("missing.pdf")))
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            fileRevealer: revealer,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")

        model.startImportEntry(
            opening: opening,
            source: .dropZone,
            urls: [
                URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf"),
                URL(fileURLWithPath: "/tmp/合同.pdf")
            ]
        )
        model.showImportEntryExistingFile(relativePath: "finance/missing.pdf")

        XCTAssertEqual(revealer.requests.map(\.relativePath), ["finance/missing.pdf"])
        XCTAssertEqual(model.toastMessage, "Existing file cannot be shown in Finder.")
    }

    @MainActor
    func testCoreDetectedDuplicateKeepBothSurvivesFooterPreviewRowReapplyBeforeImport() async {
        let invoiceURL = URL(fileURLWithPath: "/tmp/Invoice_2026Q1.pdf")
        let importer = S118SequenceBatchImporter(results: [
            .failure(CoreError.DuplicateFile(existingPath: "finance/existing-invoice.pdf")),
            .success(.s117Fixture(currentName: "Invoice_2026Q1 2.pdf", category: "finance"))
        ])
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
        )
        let rows = [s118PreviewRow(url: invoiceURL, category: "finance", suggestedName: "Invoice_2026Q1.pdf")]
        let request = s118BatchRequest(urls: [invoiceURL])

        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        model.updateDuplicateStrategy(for: rows[0].id, strategy: .keepBoth)
        model.applyPreviewRows(rows, request: request, selectedDestination: .autoClassify)
        let outcome = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .ask
            ),
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "finance",
                overrideFilename: "Invoice_2026Q1.pdf",
                duplicateStrategy: .keepBoth
            )
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.pendingDuplicateCount, 0)
        XCTAssertEqual(model.rows.map(\.status.tag), ["IMPORTED"])
    }
}

private func s118PreviewRow(
    url: URL,
    category: String,
    suggestedName: String
) -> ImportBatchPreviewRow {
    ImportBatchPreviewRow.ready(
        url: url,
        prediction: ClassifyResultSnapshot(
            category: category,
            suggestedName: suggestedName,
            reason: .keyword,
            confidence: 0.9
        )
    )
}

private func s118BatchRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs", "finance"]
    )
}

@MainActor
private final class S118RecordingFileRevealer: RepositoryFileRevealing {
    private let result: Result<Void, Error>
    private(set) var requests: [(repoPath: String, relativePath: String)] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append((repoPath: repoPath, relativePath: relativePath))
        try result.get()
    }
}
