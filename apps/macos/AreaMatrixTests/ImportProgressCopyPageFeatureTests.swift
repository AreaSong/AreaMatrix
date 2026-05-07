import XCTest
@testable import AreaMatrix

final class ImportProgressCopyPageFeatureTests: XCTestCase {
    @MainActor
    func testS120C106ProgressRouteShowsCopyRowStatesAndStopSemantics() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.runningProgress)

        guard case .importProgress(let state) = model.route else {
            return XCTFail("Expected S1-20 import progress route")
        }

        XCTAssertEqual(state.toolbarText, "Importing 1 / 3")
        XCTAssertEqual(state.items.map(\.phase), [.done, .copying, .pending])
    }

    @MainActor
    func testS120C106FailedCopyProgressKeepsFailedRowAndMappedError() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )
        let mapping = CoreErrorMappingSnapshot.s117Error(kind: .permissionDenied)

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.failedProgress)
        model.failImportEntry(progress: Self.failedProgress, mapping: mapping)

        guard case .importProgress(let state) = model.route else {
            return XCTFail("Expected S1-20 failed import progress route")
        }

        XCTAssertEqual(state.titleText, "导入已暂停")
        XCTAssertEqual(state.bannerText, "无访问权限")
        XCTAssertEqual(state.items.map(\.phase), [.done, .failed])
        XCTAssertEqual(state.items.last?.errorMessage, "无访问权限")
    }
}

private extension ImportProgressCopyPageFeatureTests {
    static let runningProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 0,
        total: 3,
        remaining: 2,
        currentPath: "docs/contract.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/contract.pdf",
                targetPath: "docs/contract.pdf",
                phase: .copying,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/later.pdf",
                targetPath: "docs/later.pdf",
                phase: .pending,
                errorMessage: nil
            ),
        ]
    )

    static let failedProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 2,
        remaining: 0,
        currentPath: "docs/contract.pdf",
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/contract.pdf",
                targetPath: "docs/contract.pdf",
                phase: .failed,
                errorMessage: "无访问权限"
            ),
        ]
    )
}
