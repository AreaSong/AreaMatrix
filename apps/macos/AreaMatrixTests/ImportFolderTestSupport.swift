@testable import AreaMatrix
import Foundation

@MainActor
func makeImportFolderPreviewModel(
    predictor: any CoreCategoryPredicting,
    importer: any CoreBatchCopyImporting = ImportBatchRecordingBatchImporter(),
    errorMapper: any CoreErrorMapping = RecordingCoreErrorMapper.importSingleFile(),
    conflictPrechecker: any ImportFolderConflictPrechecking = ImportFolderNoopConflictPrechecker(),
    scanner: any ImportFolderScanning = ImportPlatformServices.folderScanner,
    placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader()
) -> ImportFolderPreviewModel {
    ImportFolderPreviewModel(
        predictor: predictor,
        importer: importer,
        errorMapper: errorMapper,
        conflictPrechecker: conflictPrechecker,
        scanner: scanner,
        placeholderDownloader: placeholderDownloader
    )
}

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
    return makeImportFolderPreviewModel(
        predictor: ImportFolderRecordingPredictor(
            results: [.success(.importFolderPrediction(suggestedName: "name.pdf"))]
        ),
        importer: importer,
        conflictPrechecker: prechecker,
        scanner: scanner
    )
}
