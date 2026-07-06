@testable import AreaMatrix
import Foundation

func importSingleFileCoreCapabilityRequest() -> ImportEntryRequest {
    ImportEntryRequest(
        repoPath: importSingleFileRepoPath(),
        source: .filePicker,
        destination: .autoClassify,
        urls: [importSingleFileContractURL()],
        kind: .singleFile
    )
}

func importSingleFileCoreCapabilityPrediction() -> ClassifyResultSnapshot {
    .testFixture(
        category: "docs",
        suggestedName: "2026Q1_合同.pdf",
        reason: .keyword,
        confidence: 0.93
    )
}

func importSingleFileCoreCapabilityImportRequests() -> [ImportSingleFileImportRequest] {
    [
        importSingleFileImportRequest(mode: .copy, filename: "copy.pdf"),
        importSingleFileImportRequest(mode: .move, filename: "move.pdf"),
        importSingleFileImportRequest(mode: .indexOnly, filename: "indexed.pdf")
    ]
}

func importSingleFileImportRequest(
    mode: ImportSingleFileStorageMode,
    filename: String
) -> ImportSingleFileImportRequest {
    ImportSingleFileImportRequest(
        mode: mode,
        overrideCategory: "finance",
        overrideFilename: filename,
        duplicateStrategy: .ask
    )
}
