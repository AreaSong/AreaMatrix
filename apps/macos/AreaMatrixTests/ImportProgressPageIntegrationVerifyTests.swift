@testable import AreaMatrix
import XCTest

final class ImportProgressPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testS120MainListTemporaryImportRowsCanDriveDetailPane() {
        let rows = Self.runningProgress.items.map(ImportProgressListRow.init)

        XCTAssertEqual(rows.map(\.displayName), ["invoice.pdf", "contract.pdf", "later.pdf"])
        XCTAssertEqual(rows.map(\.phaseText), ["Done", "Copying", "Pending"])
        XCTAssertEqual(rows[1].sourcePath, "/tmp/contract.pdf")
        XCTAssertEqual(rows[1].targetPath, "docs/contract.pdf")
    }

    @MainActor
    func testS120FatalImportExitMustRouteThroughS121ResultSummary() {
        let opening = RepositoryOpeningResult.s117Fixture(repoPath: "/tmp/repo")
        let model = OnboardingModel(
            settingsReader: S117StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: S117RecordingAccessibilityAnnouncer(),
            helpOpener: S117NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.fatalProgress)
        model.failImportEntry(
            progress: Self.fatalProgress,
            mapping: CoreErrorMappingSnapshot.s120FatalProgressError,
            retryContext: nil,
            recoveryCheck: .retryBlocked("Recovery state could not be confirmed.", nil)
        )
        model.stopImportProgressAndViewResults()

        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected S1-21 import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 2, pending 1.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed, .skipped, .skipped, .pending])
        XCTAssertEqual(result.items[1].reason, "Storage write failed")
    }
}

private extension ImportProgressPageIntegrationVerifyTests {
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
            )
        ]
    )

    static let fatalProgress = ImportBatchProgressSnapshot(
        completed: 1,
        failed: 1,
        total: 5,
        remaining: 1,
        currentPath: "docs/contracts/合同.pdf",
        skipped: 2,
        pending: 0,
        items: [
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/invoice.pdf",
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/合同.pdf",
                targetPath: "docs/contracts/合同.pdf",
                phase: .failed,
                errorMessage: "Storage write failed"
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/skipped-a.pdf",
                targetPath: "docs/skipped-a.pdf",
                phase: .pending,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/skipped-b.pdf",
                targetPath: "docs/skipped-b.pdf",
                phase: .pending,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: "/tmp/pending.pdf",
                targetPath: "docs/pending.pdf",
                phase: .writingIndex,
                errorMessage: nil
            )
        ]
    )
}

private extension CoreErrorMappingSnapshot {
    static var s120FatalProgressError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "S1-20 fatal import progress"
        )
    }
}
