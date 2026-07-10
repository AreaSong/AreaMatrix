@testable import AreaMatrix
import XCTest

final class ImportProgressInterruptedSessionTests: XCTestCase {
    @MainActor
    func testInterruptedCopySessionRoutesToImportResultAfterRepositoryOpen() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let store = StaticImportBatchSessionStore(
            session: ImportProgressFixtures.interruptedCopySessionTwoPending
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: store,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        guard let result = await waitForImportResultRoute(model) else { return }

        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 0, stopped 0, pending 2.",
            statuses: [.imported, .pending, .pending]
        )
        XCTAssertEqual(result.items.dropFirst().map(\.reason), [
            "Import not completed before AreaMatrix quit",
            "Import not completed before AreaMatrix quit"
        ])
        XCTAssertEqual(model.toastMessage, "检测到上次未完成的批量导入。")
    }

    @MainActor
    func testInterruptedCopySessionIsClearedWhenUserAcknowledgesResults() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let store = StaticImportBatchSessionStore(
            session: ImportProgressFixtures.interruptedCopySessionOnePending
        )
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: store,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        guard await waitForImportResultRoute(model) != nil else { return }
        model.finishImportResult()
        let mainListOpening = await waitForMainListRoute(model)

        let clearedRepoPaths = await store.waitForClearedRepoPaths([importProgressRepoPath()])
        XCTAssertEqual(clearedRepoPaths, [importProgressRepoPath()])
        XCTAssertEqual(mainListOpening, opening)
    }

    @MainActor
    func testCorruptedOrMissingInterruptedCopySessionDoesNotBlockMainRoute() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: StaticImportBatchSessionStore(session: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        let mainListOpening = await waitForMainListRoute(model)

        XCTAssertEqual(mainListOpening, opening)
        XCTAssertNil(model.toastMessage)
    }
}
