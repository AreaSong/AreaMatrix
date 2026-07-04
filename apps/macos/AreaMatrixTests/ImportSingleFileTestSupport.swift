@testable import AreaMatrix
import Foundation
import XCTest

@MainActor
func makeImportSingleFilePreviewModel(
    predictor: any CoreCategoryPredicting = ImportSingleFileRecordingPredictor(result: .importSingleFileFixture()),
    importer: any CoreFileImporting = ImportSingleFileRecordingImporter(),
    preflight: any ImportSingleFilePreflighting = ImportSingleFileStaticPreflight.ready(),
    placeholderDownloader: any ICloudPlaceholderDownloading = ImportSingleFileStaticICloudDownloader(),
    errorMapper: any CoreErrorMapping = RecordingCoreErrorMapper.importSingleFile()
) -> ImportSingleFilePreviewModel {
    ImportSingleFilePreviewModel(
        predictor: predictor,
        importer: importer,
        preflight: preflight,
        placeholderDownloader: placeholderDownloader,
        errorMapper: errorMapper
    )
}

@MainActor
func importImportSingleFileMode(
    model: ImportSingleFilePreviewModel,
    request: ImportEntryRequest,
    mode: ImportSingleFileStorageMode,
    name: String,
    storageMode: String
) async {
    if mode != .copy {
        await model.load(request: request)
    }
    model.selectedCategory = " finance "
    model.selectedStorageMode = mode
    model.suggestedName = " \(name) "
    await waitForImportSingleFilePreflightToSettle(model)
    let imported = await model.importSelectedFile()
    XCTAssertEqual(imported?.storageMode, storageMode)
}
