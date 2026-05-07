import XCTest
@testable import AreaMatrix

final class ImportFolderConflictResolutionTests: XCTestCase {
    @MainActor
    func testS119FolderConflictPrecheckMapsDuplicateNameAndBlockedRows() async {
        let fixture = S119FolderConflictFixture.make()
        let model = ImportFolderPreviewModel(
            predictor: fixture.predictor,
            importer: S118RecordingBatchImporter(),
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: fixture.prechecker,
            scanner: fixture.scanner
        )

        await model.load(request: s119FolderRequest(rootURL: fixture.rootURL))
        let requests = await fixture.prechecker.recordedRequests()

        XCTAssertEqual(requests.map(\.destination), [.autoClassify])
        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "NAME", "BLOCKED"])
        XCTAssertEqual(model.duplicateCount, 1)
        XCTAssertEqual(model.nameConflictCount, 1)
        XCTAssertEqual(model.blockedCount, 1)
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        XCTAssertEqual(model.rows[0].status.detail, "Skip: docs/existing-dup.pdf")
        XCTAssertEqual(model.rows[1].status.detail, "Keep both (auto-number): docs/name.pdf")
    }

    @MainActor
    func testS119FolderConflictStrategiesControlImportQueueAndSummary() async {
        let fixture = S119FolderConflictFixture.make(includeBlocked: false)
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: fixture.predictor,
            importer: importer,
            errorMapper: S117RecordingErrorMapper(),
            conflictPrechecker: fixture.prechecker,
            scanner: fixture.scanner
        )

        await model.load(request: s119FolderRequest(rootURL: fixture.rootURL))
        model.renameIncomingFile(for: fixture.nameURL.path, to: "renamed-name.pdf")
        let outcome = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "renamed-name.pdf",
                duplicateStrategy: .keepBoth
            ),
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(outcome?.skippedDuplicateCount, 1)
        XCTAssertEqual(outcome?.total, 1)
        XCTAssertEqual(model.rows.map(\.status.tag), ["DUP", "IMPORTED"])
    }

    @MainActor
    func testS119FolderReplaceRequiresS124ConfirmationBeforeImport() async throws {
        let duplicateURL = URL(fileURLWithPath: "/tmp/client-a/dup.pdf")
        let scanner = S119StaticFolderScanner(result: ImportFolderScanResult(
            rows: [ImportFolderPreviewRow.loading(
                fileURL: duplicateURL,
                rootURL: URL(fileURLWithPath: "/tmp/client-a")
            )],
            folderCount: 0,
            skippedRules: [],
            errors: []
        ))
        let prechecker = S119StaticConflictPrechecker(results: [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf"),
        ])
        let importer = S118RecordingBatchImporter()
        let model = ImportFolderPreviewModel(
            predictor: S119RecordingPredictor(results: [.success(.s119Prediction())]),
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
        model.updateDuplicateStrategy(
            for: duplicateURL.path,
            strategy: ImportBatchDuplicateResolutionStrategy.replace
        )
        XCTAssertEqual(model.importDisabledReason, "存在 BLOCKED 项，请先完成冲突处理")
        let blockedOutcome = await model.importReadyFiles()
        XCTAssertNil(blockedOutcome)

        let context: ImportSingleFileReplaceConfirmationContext = try XCTUnwrap(
            model.beginReplaceConfirmation(for: duplicateURL.path)
        )
        model.applyReplaceConfirmation(
            for: duplicateURL.path,
            decision: context.decision(understandsReplace: true)
        )
        let outcome = await model.importReadyFiles()
        let recordedRequests = await importer.recordedRequests()

        XCTAssertEqual(recordedRequests, [
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "ready.pdf",
                duplicateStrategy: .overwrite
            ),
        ])
        XCTAssertEqual(outcome?.succeededEntries.count, 1)
        XCTAssertEqual(model.rows.first?.status.tag, "IMPORTED")
    }
}

private struct S119FolderConflictFixture {
    var rootURL: URL
    var nameURL: URL
    var scanner: S119StaticFolderScanner
    var predictor: S119MappedPredictor
    var prechecker: S119StaticConflictPrechecker

    static func make(includeBlocked: Bool = true) -> S119FolderConflictFixture {
        let rootURL = URL(fileURLWithPath: "/tmp/client-a")
        let duplicateURL = rootURL.appendingPathComponent("dup.pdf")
        let nameURL = rootURL.appendingPathComponent("name.pdf")
        let blockedURL = rootURL.appendingPathComponent("blocked.pdf")
        var rows = [
            ImportFolderPreviewRow.loading(fileURL: duplicateURL, rootURL: rootURL),
            ImportFolderPreviewRow.loading(fileURL: nameURL, rootURL: rootURL),
        ]
        var predictions: [String: Result<ClassifyResultSnapshot, Error>] = [
            "dup.pdf": .success(.s119Prediction(category: "docs", suggestedName: "dup.pdf")),
            "name.pdf": .success(.s119Prediction(category: "docs", suggestedName: "name.pdf")),
        ]
        var results: [String: ImportFolderConflictPrecheckResult] = [
            duplicateURL.path: .duplicate(existingPath: "docs/existing-dup.pdf"),
            nameURL.path: .nameConflict(existingPath: "docs/name.pdf"),
        ]

        if includeBlocked {
            rows.append(ImportFolderPreviewRow.loading(fileURL: blockedURL, rootURL: rootURL))
            predictions["blocked.pdf"] = .success(.s119Prediction(category: "docs", suggestedName: "blocked.pdf"))
            results[blockedURL.path] = .blocked("Conflict precheck failed: permission denied")
        }

        return S119FolderConflictFixture(
            rootURL: rootURL,
            nameURL: nameURL,
            scanner: S119StaticFolderScanner(result: ImportFolderScanResult(
                rows: rows,
                folderCount: 0,
                skippedRules: [],
                errors: []
            )),
            predictor: S119MappedPredictor(resultsByFilename: predictions),
            prechecker: S119StaticConflictPrechecker(results: results)
        )
    }
}
