@testable import AreaMatrix
import XCTest

// swiftlint:disable:next type_body_length
final class RenameFilePageFeatureTests: XCTestCase {
    @MainActor
    func testRenameFileRenameFileCoreSubmitRenameUsesCoreBridgeAndRefreshesListDetailAndLog() async {
        let original = FileEntrySnapshot.renameFixture(id: 122, name: "old.pdf")
        let renamed = FileEntrySnapshot.renameFixture(id: 122, name: "new.pdf", updatedAt: 1_700_000_300)
        let renamer = RenameRecordingRenamer(result: .success(renamed))
        let logEntry = ChangeLogEntrySnapshot.detailLogFixture(fileID: renamed.id, action: "renamed")
        let logLister = DetailLogRecordingLister(results: [.success([logEntry])])
        let model = MainFileListModel(
            opening: .renameFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileRenamer: renamer,
            changeLogLister: logLister,
            errorMapper: StaticCoreErrorMapper(mapping: .renameConflict())
        )

        await model.selectFiles([original.id])
        model.beginRename()
        let didRename = await model.submitRename(fileID: original.id, newName: "new.pdf")

        XCTAssertTrue(didRename)
        await renamer.assertRecordedRequests([
            RenameRequest(repoPath: "/tmp/repo", fileID: original.id, newName: "new.pdf")
        ])
        XCTAssertEqual(model.files, [renamed])
        XCTAssertEqual(model.selection, .single(renamed.id))
        XCTAssertEqual(model.selectedFileDetail, renamed)
        XCTAssertEqual(model.detailLogState, .loaded(fileID: renamed.id, entries: [logEntry]))
        XCTAssertEqual(model.detailTabRequest, .automatic(.log))
        XCTAssertNil(model.pendingActionDestination)
        XCTAssertEqual(model.renameState, .idle)
    }

    @MainActor
    func testRenameFileRenameFileCoreFailureKeepsSheetOpenInputAndMapsCoreError() async {
        let original = FileEntrySnapshot.renameFixture(id: 123, name: "old.pdf")
        let mapping = CoreErrorMappingSnapshot.renameConflict()
        let mapper = StaticCoreErrorMapper(mapping: mapping)
        let renamer = RenameRecordingRenamer(result: .failure(CoreError.Conflict(path: "docs/contracts/new.pdf")))
        let model = MainFileListModel(
            opening: .renameFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileRenamer: renamer,
            errorMapper: mapper
        )

        await model.selectFiles([original.id])
        model.beginRename()
        let didRename = await model.submitRename(fileID: original.id, newName: "new.pdf")

        XCTAssertFalse(didRename)
        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(model.selectedFileDetail, original)
        XCTAssertEqual(model.pendingActionDestination, .rename(fileID: original.id))
        XCTAssertEqual(model.renameState, .failed(fileID: original.id, mapping))
        await mapper.assertRecordedErrors([CoreError.Conflict(path: "docs/contracts/new.pdf")])
    }

    @MainActor
    func testRenameFileRenameFileCoreDetailMetaRenameEntryRoutesToSameFileActionSheet() async {
        let original = FileEntrySnapshot.renameFixture(id: 126, name: "detail.pdf")
        let model = MainFileListModel(
            opening: .renameFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            errorMapper: StaticCoreErrorMapper(mapping: .renameConflict())
        )

        await model.selectFiles([original.id])
        model.beginRename(fileID: original.id)

        XCTAssertEqual(model.pendingActionDestination, .rename(fileID: original.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "rename-file")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Rename File")
    }

    @MainActor
    func testRenameFileRenameFileCoreDetailMetaRenameEntryRespectsWriteActionLocks() async {
        let original = FileEntrySnapshot.renameFixture(id: 127, name: "locked.pdf")
        let model = MainFileListModel(
            opening: .renameFixture(
                repoPath: "/tmp/repo",
                files: [original],
                writeLockedFileIDs: [original.id]
            ),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            errorMapper: StaticCoreErrorMapper(mapping: .renameConflict())
        )

        await model.selectFiles([original.id])
        model.beginRename(fileID: original.id)

        XCTAssertEqual(model.writeActionDisabledReason(fileID: original.id), .importLocked)
        XCTAssertNil(model.pendingActionDestination)
    }

    func testRenameFileRenameFileCoreDraftValidationRejectsEmptyIllegalUnchangedAndLoadedSameDirectoryConflicts() {
        let current = FileEntrySnapshot.renameFixture(id: 124, name: "old.pdf")
        let existing = FileEntrySnapshot.renameFixture(id: 125, name: "taken.pdf")

        XCTAssertEqual(
            RenameFileDraft(file: current, candidateFiles: [current, existing], rawName: "  ").validationMessage,
            "File name is required"
        )
        XCTAssertEqual(
            RenameFileDraft(
                file: current,
                candidateFiles: [current, existing],
                rawName: "bad:name.pdf"
            ).validationMessage,
            "File name cannot contain \":\""
        )
        XCTAssertEqual(
            RenameFileDraft(
                file: current,
                candidateFiles: [current, existing],
                rawName: "bad/name.pdf"
            ).validationMessage,
            "File name cannot contain \"/\""
        )
        XCTAssertEqual(
            RenameFileDraft(
                file: current,
                candidateFiles: [current, existing],
                rawName: "bad\\name.pdf"
            ).validationMessage,
            "File name cannot contain \"\\\""
        )
        XCTAssertEqual(
            RenameFileDraft(file: current, candidateFiles: [current, existing], rawName: "..").validationMessage,
            "File name cannot be .."
        )
        XCTAssertEqual(
            RenameFileDraft(file: current, candidateFiles: [current, existing], rawName: "old.pdf").validationMessage,
            "Enter a different file name"
        )
        XCTAssertEqual(
            RenameFileDraft(file: current, candidateFiles: [current, existing], rawName: "taken.pdf").validationMessage,
            "A file with this name already exists in docs/contracts"
        )
    }

    func testRenameFileRenameFileCoreInitialEditingSelectsFilenameBodyAndLeavesExtensionVisible() {
        let current = FileEntrySnapshot.renameFixture(id: 128, name: "contract.final.pdf")
        let sheet = RenameFileSheet(
            file: current,
            candidateFiles: [current],
            state: .idle,
            onCancel: {},
            onRename: { _, _ in },
            onShowExistingFile: { _ in }
        )
        let configuration = sheet.initialEditingConfiguration

        XCTAssertTrue(configuration.focusesOnAppear)
        XCTAssertEqual(configuration.text, "contract.final.pdf")
        XCTAssertEqual(configuration.initialSelection.selectedText(in: configuration.text), "contract.final")
        XCTAssertEqual(configuration.initialSelection.unselectedSuffix(in: configuration.text), ".pdf")
    }

    func testRenameFileRenameFileCoreInitialEditingSelectsWholeNameWhenThereIsNoExtension() {
        let selection = RenameFilenameSelection.filenameBody(in: "README")

        XCTAssertEqual(selection.selectedText(in: "README"), "README")
        XCTAssertEqual(selection.unselectedSuffix(in: "README"), "")
    }

    func testRenameFileRenameFileCoreDefaultCoreBridgeRenamesRealCopiedFileAndWritesChangeLog() async throws {
        let repoURL = try makeRenameTemporaryRepositoryURL()
        let sourceRootURL = try makeRenameTemporaryRepositoryURL()
        let sourceURL = sourceRootURL.appendingPathComponent("source.pdf")
        defer {
            removeTestTemporaryItems(repoURL, sourceRootURL)
        }
        try "rename bytes".write(to: sourceURL, atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let imported = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "source.pdf",
            duplicateStrategy: .keepBoth
        )
        let renamed = try await bridge.renameFile(repoPath: repoURL.path, fileID: imported.id, newName: "renamed.pdf")
        let detail = try await bridge.getFile(repoPath: repoURL.path, fileID: imported.id)
        let changes = try await bridge.listChanges(repoPath: repoURL.path, filter: .detailLog(fileID: imported.id))

        XCTAssertEqual(renamed.id, imported.id)
        XCTAssertEqual(renamed.category, imported.category)
        XCTAssertEqual(renamed.currentName, "renamed.pdf")
        XCTAssertEqual(detail.currentName, "renamed.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("docs/renamed.pdf").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("docs/source.pdf").path))
        XCTAssertTrue(changes.contains { $0.action == "renamed" })
    }

    func testBatchRenameUndoBatchRenamePreviewCoreBatchRenameRuleSnapshotsCoverFourStrategies() {
        let prefix = BatchRenameRuleDraft(prefix: "ProjectA_").snapshot
        var date = BatchRenameRuleDraft(
            mode: .datePrefix,
            dateSource: .modified,
            dateFormat: "yyyy/MM/dd",
            separator: "-"
        )
        var sequence = BatchRenameRuleDraft(mode: .keepBaseSequence, separator: ".", startNumber: 7, padding: 3)
        var replace = BatchRenameRuleDraft(mode: .replaceText, find: "draft", replacement: "final", caseSensitive: true)

        XCTAssertEqual(prefix, .batchRenameRule(.prefix, prefix: "ProjectA_"))
        XCTAssertEqual(
            date.snapshot,
            .batchRenameRule(.datePrefix, dateSource: .modified, dateFormat: "yyyy/MM/dd", separator: "-")
        )
        XCTAssertEqual(
            sequence.snapshot,
            .batchRenameRule(.keepBaseSequence, separator: ".", startNumber: 7, padding: 3)
        )
        XCTAssertEqual(
            replace.snapshot,
            .batchRenameRule(.replaceText, find: "draft", replacement: "final", caseSensitive: true)
        )
        replace.find = " "
        date.dateFormat = " "
        sequence.padding = 0
        XCTAssertEqual(replace.validationMessage, "Find is required.")
        XCTAssertEqual(date.validationMessage, "Date format is required.")
        XCTAssertEqual(sequence.validationMessage, "Padding must be 1 or greater.")
    }

    func testBatchRenameUndoBatchRenamePreviewCoreBatchRenameValidationRequiresCurrentPreviewAndApplyState() {
        let rule = BatchRenameRuleSnapshot.batchRenameRule(.prefix, prefix: "A_")
        let preview = BatchRenamePreviewReportSnapshot.preview(rule: rule, token: "token-1", fileIDs: [1, 2])

        XCTAssertTrue(BatchRenameValidation.batchRenameUndoCanApply(fileIDs: [1, 2], preview: preview, rule: rule))
        let refreshingState = BatchRenamePreviewState.loading(previous: preview)
        XCTAssertNil(refreshingState.applyReport)
        XCTAssertEqual(refreshingState.displayReport, preview)
        XCTAssertFalse(
            BatchRenameValidation.batchRenameUndoCanApply(
                fileIDs: [1, 2],
                preview: refreshingState.applyReport,
                rule: rule
            )
        )
        XCTAssertFalse(BatchRenameValidation.batchRenameUndoCanApply(fileIDs: [1, 2], preview: nil, rule: rule))
        XCTAssertFalse(
            BatchRenameValidation.batchRenameUndoCanApply(
                fileIDs: [1, 2],
                preview: preview.with(canApply: false),
                rule: rule
            )
        )
        XCTAssertFalse(
            BatchRenameValidation.batchRenameUndoCanApply(
                fileIDs: [1, 2],
                preview: preview,
                rule: .batchRenameRule(.replaceText, find: "a")
            )
        )
        XCTAssertFalse(BatchRenameValidation.batchRenameUndoCanApply(fileIDs: [1], preview: preview, rule: rule))
        XCTAssertFalse(BatchRenameValidation.batchRenameUndoCanApply(fileIDs: [2, 1], preview: preview, rule: rule))
        XCTAssertFalse(
            BatchRenameValidation.batchRenameUndoCanApply(
                fileIDs: [1, 2],
                preview: preview,
                rule: rule,
                disabledReason: "No files selected"
            )
        )
        XCTAssertFalse(
            BatchRenameValidation.batchRenameUndoCanApply(
                fileIDs: [1, 2],
                preview: preview,
                rule: rule,
                isApplying: true
            )
        )
    }

    func testBatchRenameUndoBatchRenamePreviewCoreBatchRenameActionCallsPreviewAndApplyWithPreviewToken() async {
        let rule = BatchRenameRuleSnapshot.batchRenameRule(
            .keepBaseSequence,
            separator: "_",
            startNumber: 1,
            padding: 2
        )
        let preview = BatchRenamePreviewReportSnapshot.preview(rule: rule, token: "preview-token", fileIDs: [11, 12])
        let report = BatchRenameReportSnapshot.report(token: "undo-token")
        let renamer = BatchRenameRecordingRenamer(preview: .success(preview), apply: .success(report))
        let mapper = StaticCoreErrorMapper(mapping: .batchRenameConflict)

        let loadedPreview = await BatchRenameAction.batchRenameUndoPreview(
            rule: rule,
            renamer: renamer,
            errorMapper: mapper
        )
        let applyResult = await BatchRenameAction.batchRenameUndoApply(
            preview: preview,
            renamer: renamer,
            errorMapper: mapper
        )

        XCTAssertEqual(loadedPreview.applyReport, preview)
        XCTAssertEqual(applyResult.report, report)
        await renamer.assertPreviewRequests([
            BatchRenamePreviewRequest(repoPath: "/repo", fileIDs: [11, 12], rule: rule)
        ])
        await renamer.assertApplyRequests([
            BatchRenameApplyRequest(repoPath: "/repo", fileIDs: [11, 12], rule: rule, token: "preview-token")
        ])
    }

    func testBatchRenameUndoBatchRenamePreviewCoreBatchRenameUsesCurrentListOrderForPreviewAndApply() async {
        let rule = BatchRenameRuleSnapshot.batchRenameRule(
            .keepBaseSequence,
            separator: "_",
            startNumber: 1,
            padding: 2
        )
        let preview = BatchRenamePreviewReportSnapshot.preview(
            rule: rule,
            token: "preview-token",
            fileIDs: [30, 10, 20]
        )
        let renamer = BatchRenameRecordingRenamer(preview: .success(preview), apply: .success(.report()))
        let mapper = StaticCoreErrorMapper(mapping: .batchRenameConflict)

        let loadedPreview = await BatchRenameAction.preview(
            repoPath: "/repo",
            fileIDs: [30, 10, 20],
            rule: rule,
            renamer: renamer,
            errorMapper: mapper
        )
        _ = await BatchRenameAction.apply(
            repoPath: "/repo",
            fileIDs: [30, 10, 20],
            preview: preview,
            renamer: renamer,
            errorMapper: mapper
        )

        XCTAssertEqual(loadedPreview.applyReport?.items.map(\.fileID), [30, 10, 20])
        await renamer.assertPreviewRequests([
            BatchRenamePreviewRequest(repoPath: "/repo", fileIDs: [30, 10, 20], rule: rule)
        ])
        await renamer.assertApplyRequests([
            BatchRenameApplyRequest(repoPath: "/repo", fileIDs: [30, 10, 20], rule: rule, token: "preview-token")
        ])
    }

    func testBatchRenameUndoBatchRenamePreviewCoreBatchRenameEntryUsesListOrderInsteadOfIDOrNameOrder() {
        let firstInList = FileEntrySnapshot.renameFixture(id: 30, name: "zeta.pdf")
        let secondInList = FileEntrySnapshot.renameFixture(id: 10, name: "alpha.pdf")
        let thirdInList = FileEntrySnapshot.renameFixture(id: 20, name: "middle.pdf")
        let summary = MultiSelectionDetailSummary(
            selection: .multiple([10, 20, 30]),
            files: [firstInList, secondInList, thirdInList]
        )

        XCTAssertEqual(BatchRenameEntryPolicy.fileIDsForPreview(summary: summary), [30, 10, 20])
        XCTAssertEqual(summary.files.map(\.id), [10, 20, 30])
    }

    func testBatchRenameUndoBatchRenamePreviewCoreBatchRenameActionMapsPreviewAndApplyErrors() async {
        let rule = BatchRenameRuleSnapshot.batchRenameRule(.replaceText, find: "draft")
        let preview = BatchRenamePreviewReportSnapshot.preview(rule: rule, token: "token", fileIDs: [9])
        let previewFailure = BatchRenameRecordingRenamer(
            preview: .failure(CoreError.InvalidPath(path: "bad")),
            apply: .success(.report())
        )
        let applyFailure = BatchRenameRecordingRenamer(
            preview: .success(preview),
            apply: .failure(CoreError.Conflict(path: "stale"))
        )
        let mapper = StaticCoreErrorMapper(mapping: .batchRenameConflict)

        let previewState = await BatchRenameAction.preview(
            repoPath: "/repo",
            fileIDs: [9],
            rule: rule,
            renamer: previewFailure,
            errorMapper: mapper
        )
        let applyResult = await BatchRenameAction.apply(
            repoPath: "/repo",
            fileIDs: [9],
            preview: preview,
            renamer: applyFailure,
            errorMapper: mapper
        )

        XCTAssertEqual(previewState.failure, .batchRenameConflict)
        XCTAssertEqual(applyResult.failure, .batchRenameConflict)
        await mapper.assertRecordedErrorCount(2)
    }
}
