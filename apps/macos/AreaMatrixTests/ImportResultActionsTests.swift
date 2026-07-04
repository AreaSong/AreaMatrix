@testable import AreaMatrix
import XCTest

final class ImportResultActionsTests: XCTestCase {
    @MainActor
    func testImportResultSkippedDuplicateCanShowExistingFileFromResultSummary() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importResultRepoPath())
        let revealer = RecordingRepositoryFileRevealer()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            fileRevealer: revealer,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(ImportResultFixtures.skippedDuplicateProgress)
        guard case let .importResult(result) = model.route,
              let skippedItem = result.items.first(where: { $0.status == .skipped })
        else {
            return XCTFail("Expected skipped duplicate result item")
        }

        model.showImportResultExistingFile(itemID: skippedItem.id)

        XCTAssertEqual(revealer.requests.map(\.repoPath), [importResultRepoPath()])
        XCTAssertEqual(revealer.requests.map(\.relativePath), [importResultTargetPath(importResultExistingFilename())])
        XCTAssertNil(model.toastMessage)
    }

    @MainActor
    func testTagSuggestionsTagSuggestionsCoreImportResultQueuesTagSuggestionReviewForImportedFile() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importResultRepoPath())
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(ImportResultFixtures.importedProgress)
        guard case let .importResult(result) = model.route,
              let importedItem = result.items.first(where: { $0.canReviewTagSuggestions })
        else {
            return XCTFail("Expected imported result item with tag-suggestions review action")
        }

        model.reviewImportResultTagSuggestions(itemID: importedItem.id)

        XCTAssertEqual(model.pendingTagSuggestionFocus?.fileID, 117)
        XCTAssertEqual(model.pendingTagSuggestionFocus?.source, .importResult)
        guard case let .mainList(mainOpening) = model.route else {
            return XCTFail("Expected main list route for tag-suggestions tag suggestions")
        }
        XCTAssertTrue(
            mainOpening.currentCategoryFiles.contains {
                $0.id == 117 && $0.path == importResultTargetPath(importResultImportedFilename())
            }
        )
    }

    @MainActor
    func testImportResultExportDetailsUsesRedactedPathsAndPrivacyState() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importResultRepoPath())
        let exporter = ImportResultExporter()
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            importResultExporter: exporter,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.showImportEntryResults(ImportResultFixtures.failedCopyProgress)
        model.requestImportResultExportPrivacyConfirmation()
        guard case let .importResult(confirming) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(confirming.exportState, .confirmingPrivacy)

        model.exportImportResultDetails()

        XCTAssertEqual(exporter.requests.map(\.suggestedFilename), [importResultExportFilename()])
        XCTAssertTrue(exporter.requests.first?.details.contains(".../failed.pdf") == true)
        XCTAssertFalse(exporter.requests.first?.details.contains(importResultFailedSourcePath()) == true)
        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.exportState, .exported(importResultExportPath()))
        XCTAssertEqual(model.toastMessage, "Import result details exported.")
    }
}
