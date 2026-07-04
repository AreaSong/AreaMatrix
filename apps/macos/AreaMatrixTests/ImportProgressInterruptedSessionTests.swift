@testable import AreaMatrix
import XCTest

final class ImportProgressInterruptedSessionTests: XCTestCase {
    @MainActor
    func testInterruptedCopySessionRoutesToImportResultAfterRepositoryOpen() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let store = StaticImportBatchSessionStore(session: ImportBatchSessionSnapshot(
            repoPath: importProgressRepoPath(),
            storageMode: .copy,
            completed: 1,
            failed: 0,
            total: 3,
            currentPath: "finance/first.pdf",
            items: [
                ImportBatchProgressSnapshot.Item(
                    sourcePath: importProgressQueuedSourcePath("first.pdf"),
                    targetPath: "finance/first.pdf",
                    phase: .done,
                    errorMessage: nil
                ),
                ImportBatchProgressSnapshot.Item(
                    sourcePath: importProgressQueuedSourcePath("second.pdf"),
                    targetPath: "docs/second.pdf",
                    phase: .copying,
                    errorMessage: nil
                ),
                ImportBatchProgressSnapshot.Item(
                    sourcePath: importProgressQueuedSourcePath("third.pdf"),
                    targetPath: "docs/third.pdf",
                    phase: .pending,
                    errorMessage: nil
                )
            ]
        ))
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            startupRecoverer: StaticStartupRecoverer(),
            importBatchSessionStore: store,
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.finishSuccessfulRepositoryOpen(opening)
        guard let result = await waitForImportResultRoute(model) else { return }

        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 0, stopped 0, pending 2.")
        XCTAssertEqual(result.items.map(\.status), [
            ImportResultRouteState.ItemStatus.imported,
            .pending,
            .pending
        ])
        XCTAssertEqual(result.items.dropFirst().map(\.reason), [
            "Import not completed before AreaMatrix quit",
            "Import not completed before AreaMatrix quit"
        ])
        XCTAssertEqual(model.toastMessage, "检测到上次未完成的批量导入。")
    }

    @MainActor
    func testInterruptedCopySessionIsClearedWhenUserAcknowledgesResults() async {
        let opening = RepositoryOpeningResult.mainLoadingFixture(repoPath: importProgressRepoPath(), fileCount: 1)
        let store = StaticImportBatchSessionStore(session: ImportBatchSessionSnapshot(
            repoPath: importProgressRepoPath(),
            storageMode: .copy,
            completed: 1,
            failed: 0,
            total: 2,
            currentPath: "finance/first.pdf",
            items: [
                ImportBatchProgressSnapshot.Item(
                    sourcePath: importProgressQueuedSourcePath("first.pdf"),
                    targetPath: "finance/first.pdf",
                    phase: .done,
                    errorMessage: nil
                ),
                ImportBatchProgressSnapshot.Item(
                    sourcePath: importProgressQueuedSourcePath("second.pdf"),
                    targetPath: "docs/second.pdf",
                    phase: .pending,
                    errorMessage: nil
                )
            ]
        ))
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
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        let clearedRepoPaths = await store.clearedRepoPaths()
        XCTAssertEqual(clearedRepoPaths, [importProgressRepoPath()])
        XCTAssertEqual(model.route, OnboardingModel.Route.mainList(opening))
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
        for _ in 0 ..< 20 {
            await Task.yield()
        }

        XCTAssertEqual(model.route, OnboardingModel.Route.mainList(opening))
        XCTAssertNil(model.toastMessage)
    }
}
