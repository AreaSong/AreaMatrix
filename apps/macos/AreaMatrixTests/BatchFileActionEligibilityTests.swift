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

    func testBatchActionEntryPoliciesShareEligibilityRules() {
        let first = FileEntrySnapshot.batchActionEligibilityFixture(id: 410, name: "first.pdf")
        let second = FileEntrySnapshot.batchActionEligibilityFixture(id: 411, name: "second.pdf")
        let scenarios = BatchActionEligibilityScenario.defaults(first: first, second: second)

        for scenario in scenarios {
            assertSharedEligibility(scenario)
        }
    }

    func testMultiSelectionEligibilityKeepsUpdatingBehaviorExplicit() {
        let first = FileEntrySnapshot.batchActionEligibilityFixture(id: 510, name: "first.pdf")
        let second = FileEntrySnapshot.batchActionEligibilityFixture(id: 511, name: "second.pdf")
        let summary = MultiSelectionDetailSummary(
            selection: .multiple([first.id, second.id]),
            files: [first, second],
            isUpdating: true
        )
        XCTAssertNil(MainFileBatchActionEligibility.disabledReason(
            summary: summary,
            blocksWhileUpdating: false,
            writeActionDisabledReason: { _ in nil }
        ))
        XCTAssertEqual(
            MainFileBatchActionEligibility.disabledReason(
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
            MainFileBatchActionEligibility.disabledReason(
                summary: empty,
                blocksWhileUpdating: false,
                writeActionDisabledReason: { _ in nil }
            ),
            "No files selected"
        )
        XCTAssertEqual(
            MainFileBatchActionEligibility.disabledReason(
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
        let commandDelete = CommandPaletteBatchRouteBuilder.batchDeleteRoute(context: context)
        let commandRename = CommandPaletteBatchRouteBuilder.batchRenameRoute(context: context)

        XCTAssertEqual(addTags.fileIDs, context.fileIDs)
        XCTAssertEqual(addTags.selectedCount, context.selectedCount)
        XCTAssertEqual(addTags.disabledReason, context.disabledReason)
        assertBatchRoute(changeCategory, matches: context)
        assertBatchRoute(delete, matches: context)
        assertBatchRoute(rename, matches: context)
        assertBatchRoute(commandDelete, matches: context)
        assertBatchRoute(commandRename, matches: context)
    }

    private func assertSharedEligibility(
        _ scenario: BatchActionEligibilityScenario,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sharedReason = MainFileBatchActionEligibility.disabledReason(
            selectedFiles: scenario.selectedFiles,
            isReadOnly: scenario.isReadOnly,
            isLoading: scenario.isLoading,
            writeLockedFileIDs: scenario.writeLockedFileIDs
        )

        XCTAssertEqual(sharedReason, scenario.expectedReason, scenario.name, file: file, line: line)
        assertEntryPolicyReasons(match: sharedReason, scenario, file: file, line: line)
    }

    private func assertEntryPolicyReasons(
        match sharedReason: String?,
        _ scenario: BatchActionEligibilityScenario,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(
            BatchAddTagsEntryPolicy.disabledReason(for: scenario),
            sharedReason,
            file: file,
            line: line
        )
        XCTAssertEqual(
            BatchChangeCategoryEntryPolicy.disabledReason(for: scenario),
            sharedReason,
            file: file,
            line: line
        )
        XCTAssertEqual(
            BatchDeleteEntryPolicy.disabledReason(for: scenario),
            sharedReason,
            file: file,
            line: line
        )
        XCTAssertEqual(
            BatchRenameEntryPolicy.disabledReason(for: scenario),
            sharedReason,
            file: file,
            line: line
        )
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

private extension BatchAddTagsEntryPolicy {
    static func disabledReason(for scenario: BatchActionEligibilityScenario) -> String? {
        disabledReason(
            selectedFiles: scenario.selectedFiles,
            isReadOnly: scenario.isReadOnly,
            isLoading: scenario.isLoading,
            writeLockedFileIDs: scenario.writeLockedFileIDs
        )
    }
}

private extension BatchChangeCategoryEntryPolicy {
    static func disabledReason(for scenario: BatchActionEligibilityScenario) -> String? {
        disabledReason(
            selectedFiles: scenario.selectedFiles,
            isReadOnly: scenario.isReadOnly,
            isLoading: scenario.isLoading,
            writeLockedFileIDs: scenario.writeLockedFileIDs
        )
    }
}

private extension BatchDeleteEntryPolicy {
    static func disabledReason(for scenario: BatchActionEligibilityScenario) -> String? {
        disabledReason(
            selectedFiles: scenario.selectedFiles,
            isReadOnly: scenario.isReadOnly,
            isLoading: scenario.isLoading,
            writeLockedFileIDs: scenario.writeLockedFileIDs
        )
    }
}

private extension BatchRenameEntryPolicy {
    static func disabledReason(for scenario: BatchActionEligibilityScenario) -> String? {
        disabledReason(
            selectedFiles: scenario.selectedFiles,
            isReadOnly: scenario.isReadOnly,
            isLoading: scenario.isLoading,
            writeLockedFileIDs: scenario.writeLockedFileIDs
        )
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
