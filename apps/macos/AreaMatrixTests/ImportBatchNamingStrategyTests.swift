import XCTest
@testable import AreaMatrix

final class ImportBatchNamingStrategyTests: XCTestCase {
    @MainActor
    func testS118BatchNamingStrategiesUpdateImportFilenames() async {
        let unsafeURL = URL(fileURLWithPath: "/tmp/Quarter:Plan?.pdf")
        let importer = S118RecordingBatchImporter()
        let model = ImportBatchCopyImportModel(
            importer: importer,
            errorMapper: S117RecordingErrorMapper()
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
            ),
        ]

        model.applyPreviewRows(
            rows,
            request: s118NamingRequest(urls: [unsafeURL]),
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
            S118BatchImportRequest(
                destination: .autoClassify,
                suggestedCategory: "docs",
                overrideFilename: "Batch-Quarter-Plan-.pdf",
                duplicateStrategy: .ask
            ),
        ])
    }
}

private func s118NamingRequest(urls: [URL]) -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: "/tmp/repo",
        source: .dropZone,
        destination: .autoClassify,
        urls: urls,
        kind: .multipleItems(urls.count),
        availableCategories: ["inbox", "docs"]
    )
}
