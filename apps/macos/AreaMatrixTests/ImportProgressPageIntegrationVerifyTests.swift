@testable import AreaMatrix
import XCTest

final class ImportProgressPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testImportProgressMainListTemporaryImportRowsCanDriveDetailPane() {
        let rows = ImportProgressFixtures.runningCopyProgress.items.map(ImportProgressListRow.init)

        XCTAssertEqual(rows.map(\.displayName), ["invoice.pdf", "contract.pdf", "later.pdf"])
        XCTAssertEqual(rows.map(\.statusText), ["Imported", "Copying file", "Queued"])
        XCTAssertEqual(rows[1].sourcePath, importProgressBatchSourcePath("contract.pdf"))
        XCTAssertEqual(rows[1].targetPath, "docs/contract.pdf")
    }

    @MainActor
    func testImportProgressFatalImportExitMustRouteThroughImportResultResultSummary() {
        let opening = RepositoryOpeningResult.importSingleFileFixture(repoPath: importProgressRepoPath())
        let model = OnboardingModel(
            settingsReader: StaticSettingsReader(repoPath: nil),
            accessibilityAnnouncer: RecordingAccessibilityAnnouncer(),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.route = .mainList(opening)
        model.updateImportEntryProgress(Self.fatalProgress)
        model.failImportEntry(
            progress: Self.fatalProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalProgressError,
            retryContext: nil,
            recoveryCheck: .retryBlocked("Recovery state could not be confirmed.", nil)
        )
        model.stopImportProgressAndViewResults()

        guard case let .importResult(result) = model.route else {
            return XCTFail("Expected import-result import result route")
        }
        XCTAssertEqual(result.resultSummaryText, "Imported 1, failed 1, stopped 2, pending 1.")
        XCTAssertEqual(result.items.map(\.status), [.imported, .failed, .skipped, .skipped, .pending])
        XCTAssertEqual(result.items[1].reason, "Storage write failed")
    }
}

private extension ImportProgressPageIntegrationVerifyTests {
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
                sourcePath: importProgressBatchSourcePath("invoice.pdf"),
                targetPath: "finance/invoice.pdf",
                phase: .done,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: importProgressBatchSourcePath("合同.pdf"),
                targetPath: "docs/contracts/合同.pdf",
                phase: .failed,
                errorMessage: "Storage write failed"
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: importProgressBatchSourcePath("skipped-a.pdf"),
                targetPath: "docs/skipped-a.pdf",
                phase: .pending,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: importProgressBatchSourcePath("skipped-b.pdf"),
                targetPath: "docs/skipped-b.pdf",
                phase: .pending,
                errorMessage: nil
            ),
            ImportBatchProgressSnapshot.Item(
                sourcePath: importProgressBatchSourcePath("pending.pdf"),
                targetPath: "docs/pending.pdf",
                phase: .writingIndex,
                errorMessage: nil
            )
        ]
    )
}

private extension CoreErrorMappingSnapshot {
    static var importProgressFatalProgressError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "import-progress fatal import progress"
        )
    }
}
