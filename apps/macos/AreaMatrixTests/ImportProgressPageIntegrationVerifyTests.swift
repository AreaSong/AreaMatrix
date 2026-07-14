@testable import AreaMatrix
import XCTest

final class ImportProgressPageIntegrationVerifyTests: XCTestCase {
    @MainActor
    func testImportProgressMainListTemporaryImportRowsCanDriveDetailPane() {
        let presentation = ImportProgressListPresentation(items: ImportProgressFixtures.runningCopyProgress.items)
        var selectionState = ImportProgressListSelectionState()
        let rows = presentation.rows

        XCTAssertEqual(rows.map(\.displayName), ["invoice.pdf", "contract.pdf", "later.pdf"])
        XCTAssertEqual(rows.map(\.statusText), ["Imported", "Copying file", "Queued"])
        XCTAssertEqual(rows[1].sourcePath, importProgressBatchSourcePath("contract.pdf"))
        XCTAssertEqual(rows[1].targetPath, "docs/contract.pdf")

        selectionState.selectedIDs = [rows[1].id]
        XCTAssertEqual(selectionState.selectedRow(in: presentation), rows[1])
    }

    @MainActor
    func testImportProgressFatalImportExitMustRouteThroughImportResultResultSummary() {
        let model = makeImportProgressMainListFixture().model

        model.updateImportEntryProgress(Self.fatalProgress)
        model.failImportEntry(
            progress: Self.fatalProgress,
            mapping: CoreErrorMappingSnapshot.importProgressFatalProgressError,
            retryContext: nil,
            recoveryCheck: .retryBlocked("Recovery state could not be confirmed.", nil)
        )
        model.stopImportProgressAndViewResults()

        guard let result = requireImportResultRoute(model) else { return }
        assertImportResultSummary(
            result,
            summaryText: "Imported 1, failed 1, stopped 2, pending 1.",
            statuses: [.imported, .failed, .skipped, .skipped, .pending]
        )
        XCTAssertEqual(result.items[1].reason, "Storage write failed")
    }
}

private extension ImportProgressPageIntegrationVerifyTests {
    static let fatalProgress = importBatchProgress(
        completed: 1,
        failed: 1,
        total: 5,
        remaining: 1,
        currentPath: "docs/contracts/合同.pdf",
        skipped: 2,
        pending: 0,
        items: [
            importBatchProgressItem(
                sourcePath: importProgressBatchSourcePath("invoice.pdf"),
                targetPath: "finance/invoice.pdf",
                phase: .done
            ),
            importBatchProgressItem(
                sourcePath: importProgressBatchSourcePath("合同.pdf"),
                targetPath: "docs/contracts/合同.pdf",
                phase: .failed,
                errorMessage: "Storage write failed"
            ),
            importBatchProgressItem(
                sourcePath: importProgressBatchSourcePath("skipped-a.pdf"),
                targetPath: "docs/skipped-a.pdf",
                phase: .pending
            ),
            importBatchProgressItem(
                sourcePath: importProgressBatchSourcePath("skipped-b.pdf"),
                targetPath: "docs/skipped-b.pdf",
                phase: .pending
            ),
            importBatchProgressItem(
                sourcePath: importProgressBatchSourcePath("pending.pdf"),
                targetPath: "docs/pending.pdf",
                phase: .writingIndex
            )
        ]
    )
}

private extension CoreErrorMappingSnapshot {
    static var importProgressFatalProgressError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "import-progress fatal import progress"
        )
    }
}
