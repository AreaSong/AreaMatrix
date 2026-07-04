@testable import AreaMatrix
import Foundation

@MainActor
func importFolderReplaceConfirmationModel(
    rootURL: URL,
    sourceURL: URL,
    importer: ImportBatchRecordingBatchImporter
) -> ImportFolderPreviewModel {
    let scanner = ImportFolderStaticFolderScanner(result: ImportFolderScanResult(
        rows: [ImportFolderPreviewRow.loading(fileURL: sourceURL, rootURL: rootURL)],
        folderCount: 0,
        skippedRules: [],
        errors: []
    ))
    let prechecker = ImportFolderStaticConflictPrechecker(results: [
        sourceURL.path: .nameConflict(existingPath: "docs/name.pdf")
    ])
    return ImportFolderPreviewModel(
        predictor: ImportFolderRecordingPredictor(
            results: [.success(.importFolderPrediction(suggestedName: "name.pdf"))]
        ),
        importer: importer,
        errorMapper: RecordingCoreErrorMapper.importSingleFile(),
        conflictPrechecker: prechecker,
        scanner: scanner
    )
}
