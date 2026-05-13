@testable import AreaMatrix
import XCTest

final class ImportResultCopyRetryTests: XCTestCase {
    @MainActor
    func testS121C106RetryFailedCopyItemUsesCoreBridgeImporterAndUpdatesResult() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let importer = S117RecordingImporter()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        await model.retryImportResultFailedItems()
        let requests = await importer.recordedRequests()

        XCTAssertEqual(requests, [
            S117ImportRequest(
                mode: .copy,
                overrideCategory: "docs",
                overrideFilename: "failed.pdf",
                duplicateStrategy: .ask
            )
        ])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 2, failed 0, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .imported])
        XCTAssertFalse(result.canRetryFailedItems)
        XCTAssertFalse(result.isRetryingFailedItems)
    }

    @MainActor
    func testS121RetryFailedRoutesThroughS120ProgressBeforeReturningResults() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let gate = S117ImportGate()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressImporter: S117SuspendingImporter(gate: gate),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        let retryTask = Task { await model.retryImportResultFailedItems() }
        await gate.waitUntilStarted()

        guard case let .importProgress(progress) = model.route else {
            await gate.finish()
            await retryTask.value
            return XCTFail("Expected S1-20 import progress while retrying failed S1-21 items")
        }
        XCTAssertEqual(progress.resultSummaryText, "Imported 0, failed 0, stopped 0, pending 1.")
        XCTAssertEqual(progress.items.map(\.sourcePath), ["/tmp/failed.pdf"])
        XCTAssertEqual(progress.items.map(\.phase), [.copying])

        await gate.finish()
        await retryTask.value
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result after retry completes")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 2, failed 0, stopped 0, pending 0.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .imported])
    }

    @MainActor
    func testS121C106RetryFailedCopyItemMapsErrorAndKeepsRetryableRow() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let importer = S117FailingImporter(error: CoreError.PermissionDenied(path: "/tmp/failed.pdf"))
        let errorMapper = S117RecordingErrorMapper()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importProgressImporter: importer,
            errorMapper: errorMapper,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        await model.retryImportResultFailedItems()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.PermissionDenied(path: "/tmp/failed.pdf")])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 0, pending 0.")
        XCTAssertEqual(result.items.last?.status, .failed)
        XCTAssertEqual(result.items.last?.reason, "无访问权限")
        XCTAssertTrue(result.canRetryFailedItems)
        XCTAssertFalse(result.isRetryingFailedItems)
    }

    @MainActor
    func testS121C113LoadsImportChangeLogThroughCoreBridge() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let lister = S121RecordingChangeLogLister(results: [.success([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: "imported.pdf")
        ])])
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.importedProgress)
        await model.loadImportResultChangeLog()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [S121ChangeLogRequest(repoPath: "/tmp/repo", filter: .importResultRecent)])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.changeLog, .loaded([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: "imported.pdf")
        ]))
    }

    @MainActor
    func testS121C113MapsListChangesFailureInline() async {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let lister = S121RecordingChangeLogLister(results: [.failure(CoreError.Db(message: "change log locked"))])
        let errorMapper = S117RecordingErrorMapper()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            errorMapper: errorMapper,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.importedProgress)
        await model.loadImportResultChangeLog()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "change log locked")])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.changeLog, .failed(.s117Error(kind: .db)))
    }

    func testS121ChangeLogDetailSummaryRedactsImportedSourcePath() {
        let entry = ChangeLogEntrySnapshot.importResultFixture(
            detailJSON: #"{"source":"/Users/as/private/imported.pdf","mode":"copied","category":"docs"}"#
        )

        XCTAssertTrue(entry.detailSummary.contains("source: .../imported.pdf"))
        XCTAssertFalse(entry.detailSummary.contains("/Users/as/private"))
    }

    @MainActor
    func testS121SkippedDuplicateCanShowExistingFileFromResultSummary() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let revealer = S121RecordingFileRevealer()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            fileRevealer: revealer,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.skippedDuplicateProgress)
        guard case let .importResult(result) = model.route,
              let skippedItem = result.items.first(where: { $0.status == .skipped })
        else {
            return XCTFail("Expected skipped duplicate result item")
        }

        model.showImportResultExistingFile(itemID: skippedItem.id)

        XCTAssertEqual(revealer.requests.map(\.repoPath), ["/tmp/repo"])
        XCTAssertEqual(revealer.requests.map(\.relativePath), ["docs/existing.pdf"])
        XCTAssertNil(model.toastMessage)
    }

    @MainActor
    func testS121ExportDetailsUsesRedactedPathsAndPrivacyState() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let exporter = S121RecordingImportResultExporter()
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            importResultExporter: exporter,
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(Self.failedCopyProgress)
        model.requestImportResultExportPrivacyConfirmation()
        guard case let .importResult(confirming) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(confirming.exportState, .confirmingPrivacy)

        model.exportImportResultDetails()

        XCTAssertEqual(exporter.requests.map(\.suggestedFilename), ["AreaMatrix-Import-Result.txt"])
        XCTAssertTrue(exporter.requests.first?.details.contains(".../failed.pdf") == true)
        XCTAssertFalse(exporter.requests.first?.details.contains("/tmp/failed.pdf") == true)
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.exportState, .exported("/tmp/AreaMatrix-Import-Result.txt"))
        XCTAssertEqual(model.toastMessage, "Import result details exported.")
    }
}

private extension ImportResultCopyRetryTests {
    static let importedProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 1,
        remaining: 0,
        currentPath: "docs/imported.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/imported.pdf",
                targetPath: "docs/imported.pdf",
                phase: .done,
                errorMessage: nil
            )
        ]
    )

    static let failedCopyProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: "docs/failed.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/imported.pdf",
                targetPath: "docs/imported.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/failed.pdf",
                targetPath: "docs/failed.pdf",
                phase: .failed,
                errorMessage: "无访问权限"
            )
        ]
    )

    static let skippedDuplicateProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 2,
        remaining: 0,
        currentPath: "docs/imported.pdf",
        skipped: 1,
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/Users/as/private/imported.pdf",
                targetPath: "docs/imported.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/Users/as/private/existing.pdf",
                targetPath: "docs/existing.pdf",
                phase: .pending,
                errorMessage: "Duplicate skipped",
                existingRelativePath: "docs/existing.pdf"
            )
        ]
    )
}

private struct S121ChangeLogRequest: Equatable {
    var repoPath: String
    var filter: ChangeFilterSnapshot
}

private actor S121RecordingChangeLogLister: CoreChangeLogListing {
    enum Result {
        case success([ChangeLogEntrySnapshot])
        case failure(Error)
    }

    private var results: [Result]
    private var requests: [S121ChangeLogRequest] = []

    init(results: [Result]) {
        self.results = results
    }

    func listChanges(repoPath: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        requests.append(S121ChangeLogRequest(repoPath: repoPath, filter: filter))
        guard !results.isEmpty else { return [] }

        switch results.removeFirst() {
        case let .success(entries):
            return entries
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [S121ChangeLogRequest] {
        requests
    }
}

@MainActor
private final class S121RecordingFileRevealer: RepositoryFileRevealing {
    private(set) var requests: [(repoPath: String, relativePath: String)] = []

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append((repoPath: repoPath, relativePath: relativePath))
    }
}

@MainActor
private final class S121RecordingImportResultExporter: ImportResultDetailsExporting {
    private(set) var requests: [(details: String, suggestedFilename: String)] = []

    func exportDetails(_ details: String, suggestedFilename: String) throws -> String {
        requests.append((details: details, suggestedFilename: suggestedFilename))
        return "/tmp/\(suggestedFilename)"
    }
}

private extension ChangeLogEntrySnapshot {
    static func importResultFixture(
        id: Int64 = 1,
        filename: String = "imported.pdf",
        detailJSON: String = #"{"source":"/tmp/imported.pdf","mode":"copied","category":"docs"}"#
    ) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot(
            id: id,
            fileID: 10,
            filename: filename,
            category: "docs",
            action: "imported",
            detailJSON: detailJSON,
            occurredAt: 1_700_000_000
        )
    }
}
