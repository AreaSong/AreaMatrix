@testable import AreaMatrix
import XCTest

final class ImportResultChangeLogTests: XCTestCase {
    @MainActor
    func testImportResultListChangeLogCoreLoadsImportChangeLogThroughCoreBridge() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importResultRepoPath())
        let lister = ImportResultRecordingChangeLogLister(results: [.success([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: importResultImportedFilename())
        ])])
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(ImportResultFixtures.importedProgress)
        await model.loadImportResultChangeLog()
        let requests = await lister.recordedRequests()

        XCTAssertEqual(requests, [
            ImportResultChangeLogRequest(repoPath: importResultRepoPath(), filter: .importResultRecent)
        ])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.changeLog, .loaded([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: importResultImportedFilename())
        ]))
    }

    @MainActor
    func testImportResultListChangeLogCoreMapsListChangesFailureInline() async {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importResultRepoPath())
        let lister =
            ImportResultRecordingChangeLogLister(results: [.failure(CoreError.Db(message: "change log locked"))])
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importResultChangeLister: lister,
            errorMapper: errorMapper,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(ImportResultFixtures.importedProgress)
        await model.loadImportResultChangeLog()
        let mappedErrors = await errorMapper.recordedErrors()

        XCTAssertEqual(mappedErrors, [CoreError.Db(message: "change log locked")])
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.changeLog, .failed(.importSingleFileError(kind: .db)))
    }

    func testImportResultChangeLogDetailSummaryRedactsImportedSourcePath() {
        let entry = ChangeLogEntrySnapshot.importResultFixture(
            detailJSON: importResultSourceDetailJSON(
                sourcePath: importResultPrivateSourcePath(importResultImportedFilename())
            )
        )

        XCTAssertTrue(entry.detailSummary.contains("source: .../imported.pdf"))
        XCTAssertFalse(entry.detailSummary.contains("/Users/example/private"))
    }
}
