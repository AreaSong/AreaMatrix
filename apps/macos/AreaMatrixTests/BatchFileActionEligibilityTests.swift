@testable import AreaMatrix
import XCTest

final class BatchFileActionEligibilityTests: XCTestCase {
    func testSingleAndBatchWriteEligibilityShareReasonPriority() {
        let selected = FileEntrySnapshot.batchActionEligibilityFixture(id: 400, name: "selected.pdf")
        let sharedReason = MainFileWriteActionEligibility.disabledReason(
            fileID: selected.id,
            isReadOnly: true,
            isLoading: true,
            writeLockedFileIDs: [selected.id]
        )

        XCTAssertEqual(sharedReason, .repoReadOnly)
        XCTAssertEqual(
            MainFileBatchActionEligibility.disabledReason(
                selectedFiles: [selected],
                isReadOnly: true,
                isLoading: true,
                writeLockedFileIDs: [selected.id]
            ),
            sharedReason?.message
        )
    }

    func testBatchActionEntryPolicyUsesSharedEligibilityRules() {
        let first = FileEntrySnapshot.batchActionEligibilityFixture(id: 410, name: "first.pdf")
        let second = FileEntrySnapshot.batchActionEligibilityFixture(id: 411, name: "second.pdf")
        let scenarios = BatchActionEligibilityScenario.defaults(first: first, second: second)

        for scenario in scenarios {
            assertSharedEligibilityReason(scenario)
        }
    }

    func testBatchActionEntryPoliciesShareOpenHelpFormatting() {
        let reason = MainFileWriteActionDisabledReason.repoReadOnly.message

        XCTAssertEqual(BatchAddTagsEntryPolicy.openHelp(disabledReason: nil), "Add tags to the selected files")
        XCTAssertEqual(
            BatchAddTagsEntryPolicy.openHelp(disabledReason: reason),
            "Repository is read-only. You can still review selected files and tag candidates."
        )
        XCTAssertEqual(
            BatchChangeCategoryEntryPolicy.openHelp(disabledReason: reason),
            "Repository is read-only. You can still preview selected files and category impact."
        )
        XCTAssertEqual(
            BatchDeleteEntryPolicy.openHelp(disabledReason: reason),
            "Repository is read-only. Review deletion impact before any files move to Trash."
        )
        XCTAssertEqual(
            BatchRenameEntryPolicy.openHelp(disabledReason: reason),
            "Repository is read-only. Preview new file names before renaming."
        )
    }

    func testMultiSelectionEligibilityKeepsUpdatingBehaviorExplicit() {
        let first = FileEntrySnapshot.batchActionEligibilityFixture(id: 510, name: "first.pdf")
        let second = FileEntrySnapshot.batchActionEligibilityFixture(id: 511, name: "second.pdf")
        let summary = MultiSelectionDetailSummary(
            selection: .multiple([first.id, second.id]),
            files: [first, second],
            isUpdating: true
        )
        XCTAssertNil(MainFileBatchEntryPolicy.disabledReason(
            summary: summary,
            blocksWhileUpdating: false,
            writeActionDisabledReason: { _ in nil }
        ))
        XCTAssertEqual(
            MainFileBatchEntryPolicy.disabledReason(
                summary: summary,
                blocksWhileUpdating: true,
                writeActionDisabledReason: { _ in nil }
            ),
            MainFileWriteActionDisabledReason.listLoading.message
        )
    }

    func testMultiSelectionEligibilityUsesSelectionAndFileWriteBlocks() {
        let selected = FileEntrySnapshot.batchActionEligibilityFixture(id: 520, name: "selected.pdf")
        let empty = MultiSelectionDetailSummary(selection: .multiple([]), files: [])
        let locked = MultiSelectionDetailSummary(selection: .multiple([selected.id]), files: [selected])

        XCTAssertEqual(
            MainFileBatchEntryPolicy.disabledReason(
                summary: empty,
                blocksWhileUpdating: false,
                writeActionDisabledReason: { _ in nil }
            ),
            "No files selected"
        )
        XCTAssertEqual(
            MainFileBatchEntryPolicy.disabledReason(
                summary: locked,
                blocksWhileUpdating: false,
                writeActionDisabledReason: { fileID in
                    fileID == selected.id ? .importLocked : nil
                }
            ),
            MainFileWriteActionDisabledReason.importLocked.message
        )
    }

    func testBatchActionTriggerContextCarriesMultiSelectionFieldsAndExplicitUpdateGate() {
        let first = FileEntrySnapshot.batchActionEligibilityFixture(id: 530, name: "zeta.pdf")
        let second = FileEntrySnapshot.batchActionEligibilityFixture(id: 531, name: "alpha.pdf")
        let summary = MultiSelectionDetailSummary(
            selection: .multiple([first.id, second.id]),
            files: [first, second],
            isUpdating: true
        )
        let stableSummary = MultiSelectionDetailSummary(
            selection: .multiple([first.id, second.id]),
            files: [first, second]
        )

        let defaultContext = MainFileBatchActionTriggerContext.defaultAction(
            selection: .multiple([first.id, second.id]),
            summary: summary,
            writeActionDisabledReason: { _ in nil }
        )
        let updatingBlockedContext = MainFileBatchActionTriggerContext.updatingBlockedAction(
            selection: .multiple([first.id, second.id]),
            summary: summary,
            writeActionDisabledReason: { _ in nil }
        )
        let renameContext = MainFileBatchActionTriggerContext.renamePreview(
            summary: summary,
            writeActionDisabledReason: { fileID in
                fileID == second.id ? .importLocked : nil
            }
        )
        let stableRenameContext = MainFileBatchActionTriggerContext.renamePreview(
            summary: stableSummary,
            writeActionDisabledReason: { fileID in
                fileID == second.id ? .importLocked : nil
            }
        )

        XCTAssertEqual(defaultContext.fileIDs, [first.id, second.id])
        XCTAssertEqual(defaultContext.selectedFiles.map(\.id), [second.id, first.id])
        XCTAssertEqual(defaultContext.selectedCount, 2)
        XCTAssertNil(defaultContext.disabledReason)
        XCTAssertEqual(renameContext.fileIDs, [first.id, second.id])
        XCTAssertEqual(
            updatingBlockedContext.disabledReason,
            MainFileWriteActionDisabledReason.listLoading.message
        )
        XCTAssertEqual(renameContext.disabledReason, MainFileWriteActionDisabledReason.listLoading.message)
        XCTAssertEqual(stableRenameContext.disabledReason, MainFileWriteActionDisabledReason.importLocked.message)
    }

    func testBatchActionRouteContextBuildsVisibleSelectionAndSharedEligibility() {
        let first = FileEntrySnapshot.batchActionEligibilityFixture(id: 610, name: "first.pdf")
        let second = FileEntrySnapshot.batchActionEligibilityFixture(id: 611, name: "second.pdf")
        let hidden = FileEntrySnapshot.batchActionEligibilityFixture(id: 612, name: "hidden.pdf")
        let context = MainFileBatchActionRouteContext(
            selectedFileIDs: [hidden.id, second.id, first.id],
            visibleFiles: [first, second],
            isReadOnly: false,
            isLoading: false,
            writeLockedFileIDs: [second.id]
        )

        XCTAssertEqual(context.selectedFiles.map(\.id), [first.id, second.id])
        XCTAssertEqual(context.fileIDs, [first.id, second.id])
        XCTAssertEqual(context.selectedCount, 2)
        XCTAssertEqual(context.disabledReason, MainFileWriteActionDisabledReason.importLocked.message)
    }

    func testBatchRoutesShareRouteContextFields() {
        let first = FileEntrySnapshot.batchActionEligibilityFixture(id: 620, name: "first.pdf")
        let second = FileEntrySnapshot.batchActionEligibilityFixture(id: 621, name: "second.pdf")
        let context = MainFileBatchActionRouteContext(
            selectedFileIDs: [second.id, first.id],
            visibleFiles: [first, second],
            isReadOnly: false,
            isLoading: false,
            writeLockedFileIDs: [second.id]
        )

        let addTags = BatchAddTagsRoute(source: .commandPalette, context: context)
        let changeCategory = BatchChangeCategoryRoute(source: .commandPalette, context: context)
        let delete = BatchDeleteRoute(source: .commandPalette, context: context)
        let rename = BatchRenameRoute(source: .commandPalette, context: context)
        let builtAddTags = BatchFileActionRouteBuilder.batchAddTagsRoute(source: .detailMulti, context: context)
        let builtChangeCategory = BatchFileActionRouteBuilder.batchChangeCategoryRoute(
            source: .detailMulti,
            context: context
        )
        let builtDelete = BatchFileActionRouteBuilder.batchDeleteRoute(source: .detailMulti, context: context)
        let builtRename = BatchFileActionRouteBuilder.batchRenameRoute(source: .detailMulti, context: context)
        let commandAddTags = BatchFileActionRouteBuilder.commandPaletteBatchAddTagsRoute(context: context)
        let commandChangeCategory = BatchFileActionRouteBuilder.commandPaletteBatchChangeCategoryRoute(context: context)
        let commandDelete = BatchFileActionRouteBuilder.commandPaletteBatchDeleteRoute(context: context)
        let commandRename = BatchFileActionRouteBuilder.commandPaletteBatchRenameRoute(context: context)

        assertBatchRoute(addTags, matches: context)
        assertBatchRoute(changeCategory, matches: context)
        assertBatchRoute(delete, matches: context)
        assertBatchRoute(rename, matches: context)
        assertBatchRoute(builtAddTags, matches: context)
        assertBatchRoute(builtChangeCategory, matches: context)
        assertBatchRoute(builtDelete, matches: context)
        assertBatchRoute(builtRename, matches: context)
        assertBatchRoute(commandAddTags, matches: context)
        assertBatchRoute(commandChangeCategory, matches: context)
        assertBatchRoute(commandDelete, matches: context)
        assertBatchRoute(commandRename, matches: context)
        XCTAssertEqual(builtAddTags.source, .detailMulti)
        XCTAssertEqual(builtChangeCategory.source, .detailMulti)
        XCTAssertEqual(builtDelete.source, .detailMulti)
        XCTAssertEqual(builtRename.source, .detailMulti)
        XCTAssertEqual(commandAddTags.source, .commandPalette)
        XCTAssertEqual(commandChangeCategory.source, .commandPalette)
        XCTAssertEqual(commandDelete.source, .commandPalette)
        XCTAssertEqual(commandRename.source, .commandPalette)
    }

    private func assertSharedEligibilityReason(
        _ scenario: BatchActionEligibilityScenario,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sharedReason = MainFileBatchEntryPolicy.disabledReason(
            selectedFiles: scenario.selectedFiles,
            isReadOnly: scenario.isReadOnly,
            isLoading: scenario.isLoading,
            writeLockedFileIDs: scenario.writeLockedFileIDs
        )

        XCTAssertEqual(sharedReason, scenario.expectedReason, scenario.name, file: file, line: line)
    }

    private func assertBatchRoute(
        _ route: BatchAddTagsRoute,
        matches context: MainFileBatchActionRouteContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(route.fileIDs, context.fileIDs, file: file, line: line)
        XCTAssertEqual(route.selectedCount, context.selectedCount, file: file, line: line)
        XCTAssertEqual(route.disabledReason, context.disabledReason, file: file, line: line)
    }

    private func assertBatchRoute(
        _ route: BatchChangeCategoryRoute,
        matches context: MainFileBatchActionRouteContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(route.fileIDs, context.fileIDs, file: file, line: line)
        XCTAssertEqual(route.selectedFiles, context.selectedFiles, file: file, line: line)
        XCTAssertEqual(route.selectedCount, context.selectedCount, file: file, line: line)
        XCTAssertEqual(route.disabledReason, context.disabledReason, file: file, line: line)
    }

    private func assertBatchRoute(
        _ route: BatchDeleteRoute,
        matches context: MainFileBatchActionRouteContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(route.fileIDs, context.fileIDs, file: file, line: line)
        XCTAssertEqual(route.selectedFiles, context.selectedFiles, file: file, line: line)
        XCTAssertEqual(route.selectedCount, context.selectedCount, file: file, line: line)
        XCTAssertEqual(route.disabledReason, context.disabledReason, file: file, line: line)
    }

    private func assertBatchRoute(
        _ route: BatchRenameRoute,
        matches context: MainFileBatchActionRouteContext,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(route.fileIDs, context.fileIDs, file: file, line: line)
        XCTAssertEqual(route.selectedFiles, context.selectedFiles, file: file, line: line)
        XCTAssertEqual(route.selectedCount, context.selectedCount, file: file, line: line)
        XCTAssertEqual(route.disabledReason, context.disabledReason, file: file, line: line)
    }
}

private struct BatchActionEligibilityScenario {
    var name: String
    var selectedFiles: [FileEntrySnapshot]
    var isReadOnly: Bool
    var isLoading: Bool
    var writeLockedFileIDs: Set<Int64>
    var expectedReason: String?

    static func defaults(
        first: FileEntrySnapshot,
        second: FileEntrySnapshot
    ) -> [BatchActionEligibilityScenario] {
        [
            .init(name: "empty selection", expectedReason: "No files selected"),
            .init(
                name: "read-only repository",
                selectedFiles: [first],
                isReadOnly: true,
                expectedReason: MainFileWriteActionDisabledReason.repoReadOnly.message
            ),
            .init(
                name: "loading list",
                selectedFiles: [first],
                isLoading: true,
                expectedReason: MainFileWriteActionDisabledReason.listLoading.message
            ),
            .init(
                name: "import locked file",
                selectedFiles: [first, second],
                writeLockedFileIDs: [second.id],
                expectedReason: MainFileWriteActionDisabledReason.importLocked.message
            ),
            .init(name: "ready", selectedFiles: [first, second])
        ]
    }

    init(
        name: String,
        selectedFiles: [FileEntrySnapshot] = [],
        isReadOnly: Bool = false,
        isLoading: Bool = false,
        writeLockedFileIDs: Set<Int64> = [],
        expectedReason: String? = nil
    ) {
        self.name = name
        self.selectedFiles = selectedFiles
        self.isReadOnly = isReadOnly
        self.isLoading = isLoading
        self.writeLockedFileIDs = writeLockedFileIDs
        self.expectedReason = expectedReason
    }
}

private extension FileEntrySnapshot {
    static func batchActionEligibilityFixture(id: Int64, name: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(name)",
            originalName: name,
            currentName: name,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "batch-action-eligibility-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}
