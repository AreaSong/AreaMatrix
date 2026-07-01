@testable import AreaMatrix
import XCTest

final class ImportBatchNamingStrategyTests: XCTestCase {
    @MainActor
    func testImportBatchBatchNamingStrategiesUpdateImportFilenames() async {
        let unsafeURL = URL(fileURLWithPath: "/tmp/Quarter:Plan?.pdf")
        let importer = ImportBatchRecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: RecordingCoreErrorMapper.importSingleFile()
        )
        let rows = [
            ImportBatchPreviewRow.ready(
                url: unsafeURL,
                prediction: ClassifyResultSnapshot(
                    category: "docs",
                    suggestedName: "Suggested.pdf",
                    reason: .keyword,
                    confidence: 0.9
                )
            )
        ]

        model.applyPreviewRows(
            rows,
            request: importBatchNamingRequest(urls: [unsafeURL]),
            selectedDestination: .autoClassify
        )
        XCTAssertEqual(model.rows.first?.suggestedName, "Suggested.pdf")
        model.updateNamingStrategy(.normalizedCharacters)
        XCTAssertEqual(model.rows.first?.suggestedName, "Quarter-Plan-.pdf")
        model.namingPrefix = "Batch"
        model.updateNamingStrategy(.uniformPrefix)
        XCTAssertEqual(model.rows.first?.suggestedName, "Batch-Quarter-Plan-.pdf")

        _ = await model.importReadyFiles(selectedDestination: .autoClassify)
        let recordedRequests = await importer.recordedRequests()
        XCTAssertEqual(recordedRequests, [
            ImportBatchBatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "Batch-Quarter-Plan-.pdf",
                duplicateStrategy: .ask
            )
        ])
    }
}

private func importBatchNamingRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: importBatchRepoPath(),
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs"]
    )
}
