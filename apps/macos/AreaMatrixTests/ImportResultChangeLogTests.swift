@testable import AreaMatrix
import XCTest

final class ImportResultChangeLogTests: XCTestCase {
    @MainActor
    func testImportResultListChangeLogCoreLoadsImportChangeLogThroughCoreBridge() async {
        let lister = ImportResultRecordingChangeLogLister(results: [.success([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: importResultImportedFilename())
        ])])
        let model = makeImportResultMainListFixture(importResultChangeLister: lister).model

        guard showImportResultRoute(model, progress: ImportResultFixtures.importedProgress) != nil else { return }
        await model.loadImportResultChangeLog()

        await lister.assertRecordedRequests([
            ImportResultChangeLogRequest(repoPath: importResultRepoPath(), filter: .importResultRecent)
        ])
        guard let result = requireImportResultRoute(model) else { return }
        XCTAssertEqual(result.changeLog, .loaded([
            ChangeLogEntrySnapshot.importResultFixture(id: 1, filename: importResultImportedFilename())
        ]))
    }

    @MainActor
    func testImportResultListChangeLogCoreMapsListChangesFailureInline() async {
        let lister =
            ImportResultRecordingChangeLogLister(results: [.failure(CoreError.Db(message: "change log locked"))])
        let errorMapper = RecordingCoreErrorMapper.importSingleFile()
        let model = makeImportResultMainListFixture(
            importResultChangeLister: lister,
            errorMapper: errorMapper
        ).model

        guard showImportResultRoute(model, progress: ImportResultFixtures.importedProgress) != nil else { return }
        await model.loadImportResultChangeLog()

        await errorMapper.assertRecordedErrors([CoreError.Db(message: "change log locked")])
        guard let result = requireImportResultRoute(model) else { return }
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
