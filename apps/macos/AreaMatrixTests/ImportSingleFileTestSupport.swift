@testable import AreaMatrix
import AreaMatrixFeatureIngestion
import Foundation
import XCTest

@MainActor
struct ImportSingleFileMainEmptyFixture {
    let opening: RepositoryOpeningResult
    let model: OnboardingModel
    let accessibilityAnnouncer: RecordingAccessibilityAnnouncer
}

@MainActor
func makeImportSingleFileMainEmptyFixture(
    repoPath: String = importSingleFileRepoPath(),
    settingsReader: any AppSettingsReading = StaticSettingsReader(repoPath: nil),
    accessibilityAnnouncer: RecordingAccessibilityAnnouncer? = nil,
    helpOpener: any WelcomeHelpOpening = NoopWelcomeHelpOpener()
) -> ImportSingleFileMainEmptyFixture {
    let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: repoPath)
    let accessibilityAnnouncer = accessibilityAnnouncer ?? RecordingAccessibilityAnnouncer()
    let model = makeShellOnboardingModel(
        settingsReader: settingsReader,
        emptyRepositoryOpener: ImportSingleFileStaticRepositoryOpener(opening: opening),
        accessibilityAnnouncer: accessibilityAnnouncer,
        helpOpener: helpOpener
    )
    model.route = .mainEmpty(opening)
    return ImportSingleFileMainEmptyFixture(
        opening: opening,
        model: model,
        accessibilityAnnouncer: accessibilityAnnouncer
    )
}

@MainActor
struct ImportSingleFileMainListFixture {
    let opening: RepositoryOpeningResult
    let model: OnboardingModel
}

@MainActor
func makeImportSingleFileMainListFixture(
    repoPath: String = importSingleFileRepoPath(),
    settingsReader: any AppSettingsReading = StaticSettingsReader(repoPath: nil),
    systemCapabilityChecker: any OnboardingSystemCapabilityChecking = StaticOnboardingSystemCapabilityChecker(),
    accessibilityAnnouncer: (any AccessibilityAnnouncing)? = nil,
    helpOpener: any WelcomeHelpOpening = NoopWelcomeHelpOpener()
) -> ImportSingleFileMainListFixture {
    let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: repoPath)
    let fixture = makeShellMainListFixture(
        opening: opening,
        model: makeShellOnboardingModel(
            settingsReader: settingsReader,
            emptyRepositoryOpener: ImportSingleFileStaticRepositoryOpener(opening: opening),
            systemCapabilityChecker: systemCapabilityChecker,
            accessibilityAnnouncer: accessibilityAnnouncer ?? RecordingAccessibilityAnnouncer(),
            helpOpener: helpOpener
        )
    )
    return ImportSingleFileMainListFixture(opening: fixture.opening, model: fixture.model)
}

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
func assertImportSingleFileICloudPlaceholderBlocked(
    _ model: ImportSingleFilePreviewModel,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(model.showsICloudActions, file: file, line: line)
    XCTAssertNil(model.activeConflictPage, file: file, line: line)
    XCTAssertEqual(
        model.importDisabledReason,
        "The iCloud placeholder must be downloaded before importing.",
        file: file,
        line: line
    )
}

@MainActor
func assertImportSingleFileICloudDownloadFailure(
    _ model: ImportSingleFilePreviewModel,
    reason: String,
    sourcePath: String = importSingleFileSourcePath(),
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(model.showsICloudActions, file: file, line: line)
    XCTAssertFalse(model.showsRetryPreviewAction, file: file, line: line)
    XCTAssertNil(model.activeConflictPage, file: file, line: line)
    XCTAssertEqual(
        model.importDisabledReason,
        "Retry the iCloud download or switch to a local repository.",
        file: file,
        line: line
    )
    guard case let .iCloudDownloadFailed(path, failureReason) = model.currentPreflightResult?.conflict else {
        return XCTFail(
            "Expected iCloud download failure to stay on import-single recovery state",
            file: file,
            line: line
        )
    }
    XCTAssertEqual(path, sourcePath, file: file, line: line)
    XCTAssertEqual(failureReason, reason, file: file, line: line)
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
