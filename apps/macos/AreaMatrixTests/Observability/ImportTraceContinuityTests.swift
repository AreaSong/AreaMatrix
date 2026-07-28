@testable import AreaMatrix
import Foundation
import XCTest

final class ImportTraceContinuityTests: XCTestCase {
    @MainActor
    func testBatchRunSharesTraceAndAssignsIndependentOperations() async {
        let fixture = importBatchStandardBatchFixture()
        let importer = ImportTraceRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )

        model.applyPreviewRows(fixture.rows, request: fixture.request, selectedDestination: .autoClassify)
        _ = await model.importReadyFiles(selectedDestination: .autoClassify)

        let contexts = await importer.traceContexts()
        XCTAssertEqual(contexts.count, 2)
        XCTAssertEqual(Set(contexts.map(\.traceID)).count, 1)
        XCTAssertEqual(Set(contexts.map(\.operationID)).count, 2)
        XCTAssertTrue(contexts.allSatisfy { $0.retryOfOperationID == nil })
    }

    @MainActor
    func testFolderRunSharesTraceAndAssignsIndependentOperations() async {
        let urls = [
            URL(fileURLWithPath: "/tmp/client-a/first.pdf"),
            URL(fileURLWithPath: "/tmp/client-a/second.pdf")
        ]
        let importer = ImportTraceRecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: ImportFolderRecordingPredictor(results: urls.map { _ in
                .success(.importFolderPrediction())
            }),
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile(),
            conflictPrechecker: ImportFolderNoopConflictPrechecker(),
            scanner: importFolderStaticScanner(urls: urls)
        )

        await model.load(request: importFolderFolderRequest(rootURL: URL(fileURLWithPath: "/tmp/client-a")))
        _ = await model.importReadyFiles()

        let contexts = await importer.traceContexts()
        XCTAssertEqual(contexts.count, 2)
        XCTAssertEqual(Set(contexts.map(\.traceID)).count, 1)
        XCTAssertEqual(Set(contexts.map(\.operationID)).count, 2)
        XCTAssertTrue(contexts.allSatisfy { $0.retryOfOperationID == nil })
    }

    @MainActor
    func testRetryKeepsTraceAndLinksNewOperationToFailedOperation() async {
        let importer = ImportTraceRecordingFileImporter()
        let fixture = makeImportProgressMainListFixture(importProgressImporter: importer)
        let original = ImportProgressRetryContext(
            repoPath: importProgressRepoPath(),
            sourcePath: importProgressSourcePath(),
            storageMode: .copy,
            overrideCategory: "docs",
            overrideFilename: "retried.pdf",
            duplicateStrategy: .ask,
            traceID: "4f43cc95-7ec8-4301-b70a-270fe63333e1",
            operationID: "f4409899-37d0-49e2-bbeb-708566d10d3c"
        )

        fixture.model.beginImportEntryProgress(currentPath: "docs/retried.pdf", retryContext: original)
        fixture.model.failImportEntry(
            progress: ImportProgressFixtures.copyFailedProgress,
            mapping: .importProgressFatalCopyError,
            retryContext: original,
            recoveryCheck: .retryAllowed(nil)
        )
        await fixture.model.retryCurrentImportProgressItem()

        let contexts = await importer.traceContexts()
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts[0].traceID, original.traceID)
        XCTAssertEqual(contexts[0].retryOfOperationID, original.operationID)
        XCTAssertNotEqual(contexts[0].operationID, original.operationID)
    }
}
