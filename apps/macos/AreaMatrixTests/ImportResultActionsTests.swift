@testable import AreaMatrix
import XCTest

final class ImportResultActionsTests: XCTestCase {
    @MainActor
    func testSourceRetainedResultIsSuccessfulNonRetryableAndKeepsTagReview() {
        let model = makeImportResultMainListFixture().model

        guard let result = showImportResultRoute(model, progress: ImportResultFixtures.sourceRetainedProgress),
              let item = requireImportResultItem(
                  result,
                  matching: { $0.status == .sourceRetained },
                  message: "Expected source-retained result item"
              )
        else { return }

        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 0, stopped 0, pending 0.",
            statuses: [.sourceRetained]
        )
        XCTAssertFalse(result.canRetryFailedItems)
        XCTAssertTrue(item.canReviewTagSuggestions)
        XCTAssertEqual(item.fileID, 117)
        XCTAssertEqual(item.reason, L10n.string("import.result.source-retained.reason"))

        model.reviewImportResultTagSuggestions(itemID: item.id)

        XCTAssertEqual(model.pendingTagSuggestionFocus?.fileID, 117)
        XCTAssertEqual(model.pendingTagSuggestionFocus?.source, .importResult)
        guard let mainOpening = requireMainListRoute(model) else { return }
        XCTAssertTrue(mainOpening.currentCategoryFiles.contains {
            $0.id == 117 && $0.path == importResultTargetPath(importResultImportedFilename())
        })
    }

    @MainActor
    func testImportResultSkippedDuplicateCanShowExistingFileFromResultSummary() {
        let revealer = RecordingRepositoryFileRevealer()
        let model = makeImportResultMainListFixture(fileRevealer: revealer).model

        guard let result = showImportResultRoute(model, progress: ImportResultFixtures.skippedDuplicateProgress) else {
            return
        }
        guard let skippedItem = requireImportResultItem(
            result,
            matching: { $0.status == .skipped },
            message: "Expected skipped duplicate result item"
        ) else { return }

        model.showImportResultExistingFile(itemID: skippedItem.id)

        revealer.assertRevealRequests([RecordingRepositoryFileRevealer.Request(
            repoPath: importResultRepoPath(),
            relativePath: importResultTargetPath(importResultExistingFilename())
        )])
        XCTAssertNil(model.toastMessage)
    }

    @MainActor
    func testTagSuggestionsTagSuggestionsCoreImportResultQueuesTagSuggestionReviewForImportedFile() {
        let model = makeImportResultMainListFixture().model

        guard let result = showImportResultRoute(model, progress: ImportResultFixtures.importedProgress) else { return }
        guard let importedItem = requireImportResultItem(
            result,
            matching: { $0.canReviewTagSuggestions },
            message: "Expected imported result item with tag-suggestions review action"
        ) else { return }

        model.reviewImportResultTagSuggestions(itemID: importedItem.id)

        XCTAssertEqual(model.pendingTagSuggestionFocus?.fileID, 117)
        XCTAssertEqual(model.pendingTagSuggestionFocus?.source, .importResult)
        guard let mainOpening = requireMainListRoute(
            model,
            message: "Expected main list route for tag-suggestions tag suggestions"
        ) else { return }
        XCTAssertTrue(
            mainOpening.currentCategoryFiles.contains {
                $0.id == 117 && $0.path == importResultTargetPath(importResultImportedFilename())
            }
        )
    }

    @MainActor
    func testImportResultExportDetailsUsesRedactedPathsAndPrivacyState() {
        let exporter = ImportResultExporter()
        let model = makeImportResultMainListFixture(importResultExporter: exporter).model

        guard showImportResultRoute(model, progress: ImportResultFixtures.failedCopyProgress) != nil else { return }
        model.requestImportResultExportPrivacyConfirmation()
        guard let confirming = requireImportResultRoute(model) else { return }
        XCTAssertEqual(confirming.exportState, .confirmingPrivacy)

        model.exportImportResultDetails()

        exporter.assertLastExportRequest(
            suggestedFilename: importResultExportFilename(),
            detailsContains: [".../failed.pdf"],
            detailsExcludes: [importResultFailedSourcePath()]
        )
        guard let result = requireImportResultRoute(model) else { return }
        XCTAssertEqual(result.exportState, .exported(importResultExportPath()))
        XCTAssertEqual(model.toastMessage, L10n.message("Import result details exported."))
    }
}
