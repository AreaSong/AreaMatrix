@testable import AreaMatrix
import XCTest

final class RenameFilePageFeatureTests: XCTestCase {
    @MainActor
    func testS133C122SubmitRenameUsesCoreBridgeAndRefreshesListDetailAndLog() async {
        let original = FileEntrySnapshot.renameFixture(id: 122, name: "old.pdf")
        let renamed = FileEntrySnapshot.renameFixture(id: 122, name: "new.pdf", updatedAt: 1_700_000_300)
        let renamer = RenameRecordingRenamer(result: .success(renamed))
        let logEntry = ChangeLogEntrySnapshot.detailLogFixture(fileID: renamed.id, action: "renamed")
        let logLister = DetailLogRecordingLister(results: [.success([logEntry])])
        let model = MainFileListModel(
            opening: .renameFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileRenamer: renamer,
            changeLogLister: logLister,
            errorMapper: DetailMetaErrorMapper(mapping: .renameConflict())
        )

        await model.selectFiles([original.id])
        model.beginRename()
        let didRename = await model.submitRename(fileID: original.id, newName: "new.pdf")
        let requests = await renamer.recordedRequests()

        XCTAssertTrue(didRename)
        XCTAssertEqual(requests, [
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
    func testS133C122FailureKeepsSheetOpenInputAndMapsCoreError() async {
        let original = FileEntrySnapshot.renameFixture(id: 123, name: "old.pdf")
        let mapping = CoreErrorMappingSnapshot.renameConflict()
        let mapper = DetailMetaErrorMapper(mapping: mapping)
        let renamer = RenameRecordingRenamer(result: .failure(CoreError.Conflict(path: "docs/contracts/new.pdf")))
        let model = MainFileListModel(
            opening: .renameFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            fileRenamer: renamer,
            errorMapper: mapper
        )

        await model.selectFiles([original.id])
        model.beginRename()
        let didRename = await model.submitRename(fileID: original.id, newName: "new.pdf")
        let mappedErrors = await mapper.recordedErrors()

        XCTAssertFalse(didRename)
        XCTAssertEqual(model.files, [original])
        XCTAssertEqual(model.selectedFileDetail, original)
        XCTAssertEqual(model.pendingActionDestination, .rename(fileID: original.id))
        XCTAssertEqual(model.renameState, .failed(fileID: original.id, mapping))
        XCTAssertEqual(mappedErrors, [CoreError.Conflict(path: "docs/contracts/new.pdf")])
    }

    @MainActor
    func testS133C122DetailMetaRenameEntryRoutesToSameFileActionSheet() async {
        let original = FileEntrySnapshot.renameFixture(id: 126, name: "detail.pdf")
        let model = MainFileListModel(
            opening: .renameFixture(repoPath: "/tmp/repo", files: [original]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            errorMapper: DetailMetaErrorMapper(mapping: .renameConflict())
        )

        await model.selectFiles([original.id])
        model.beginRename(fileID: original.id)

        XCTAssertEqual(model.pendingActionDestination, .rename(fileID: original.id))
        XCTAssertEqual(model.pendingActionDestination?.pageID, "S1-33")
        XCTAssertEqual(model.pendingActionDestination?.pageTitle, "Rename File")
    }

    @MainActor
    func testS133C122DetailMetaRenameEntryRespectsWriteActionLocks() async {
        let original = FileEntrySnapshot.renameFixture(id: 127, name: "locked.pdf")
        let model = MainFileListModel(
            opening: .renameFixture(
                repoPath: "/tmp/repo",
                files: [original],
                writeLockedFileIDs: [original.id]
            ),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(original)),
            errorMapper: DetailMetaErrorMapper(mapping: .renameConflict())
        )

        await model.selectFiles([original.id])
        model.beginRename(fileID: original.id)

        XCTAssertEqual(model.writeActionDisabledReason(fileID: original.id), .importLocked)
        XCTAssertNil(model.pendingActionDestination)
    }

    func testS133C122DraftValidationRejectsEmptyIllegalUnchangedAndLoadedSameDirectoryConflicts() {
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

    func testS133C122InitialEditingSelectsFilenameBodyAndLeavesExtensionVisible() {
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

    func testS133C122InitialEditingSelectsWholeNameWhenThereIsNoExtension() {
        let selection = RenameFilenameSelection.filenameBody(in: "README")

        XCTAssertEqual(selection.selectedText(in: "README"), "README")
        XCTAssertEqual(selection.unselectedSuffix(in: "README"), "")
    }

    func testS133C122DefaultCoreBridgeRenamesRealCopiedFileAndWritesChangeLog() async throws {
        let repoURL = try makeRenameTemporaryRepositoryURL()
        let sourceURL = try makeRenameTemporaryRepositoryURL().appendingPathComponent("source.pdf")
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
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

    func testS214C210BatchRenameRuleSnapshotsCoverFourStrategies() {
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

    func testS214C210BatchRenameValidationRequiresCurrentPreviewAndApplyState() {
        let rule = BatchRenameRuleSnapshot.batchRenameRule(.prefix, prefix: "A_")
        let preview = BatchRenamePreviewReportSnapshot.preview(rule: rule, token: "token-1", fileIDs: [1, 2])

        XCTAssertTrue(BatchRenameValidation.s214CanApply(fileIDs: [1, 2], preview: preview, rule: rule))
        let refreshingState = BatchRenamePreviewState.loading(previous: preview)
        XCTAssertNil(refreshingState.applyReport)
        XCTAssertEqual(refreshingState.displayReport, preview)
        XCTAssertFalse(
            BatchRenameValidation.s214CanApply(
                fileIDs: [1, 2],
                preview: refreshingState.applyReport,
                rule: rule
            )
        )
        XCTAssertFalse(BatchRenameValidation.s214CanApply(fileIDs: [1, 2], preview: nil, rule: rule))
        XCTAssertFalse(
            BatchRenameValidation.s214CanApply(
                fileIDs: [1, 2],
                preview: preview.with(canApply: false),
                rule: rule
            )
        )
        XCTAssertFalse(
            BatchRenameValidation.s214CanApply(
                fileIDs: [1, 2],
                preview: preview,
                rule: .batchRenameRule(.replaceText, find: "a")
            )
        )
        XCTAssertFalse(BatchRenameValidation.s214CanApply(fileIDs: [1], preview: preview, rule: rule))
        XCTAssertFalse(BatchRenameValidation.s214CanApply(fileIDs: [2, 1], preview: preview, rule: rule))
        XCTAssertFalse(
            BatchRenameValidation.s214CanApply(
                fileIDs: [1, 2],
                preview: preview,
                rule: rule,
                disabledReason: "No files selected"
            )
        )
        XCTAssertFalse(
            BatchRenameValidation.s214CanApply(
                fileIDs: [1, 2],
                preview: preview,
                rule: rule,
                isApplying: true
            )
        )
    }

    func testS214C210BatchRenameActionCallsPreviewAndApplyWithPreviewToken() async {
        let rule = BatchRenameRuleSnapshot.batchRenameRule(
            .keepBaseSequence,
            separator: "_",
            startNumber: 1,
            padding: 2
        )
        let preview = BatchRenamePreviewReportSnapshot.preview(rule: rule, token: "preview-token", fileIDs: [11, 12])
        let report = BatchRenameReportSnapshot.report(token: "undo-token")
        let renamer = BatchRenameRecordingRenamer(preview: .success(preview), apply: .success(report))
        let mapper = BatchRenameErrorMapper(mapping: .batchRenameConflict)

        let loadedPreview = await BatchRenameAction.s214Preview(rule: rule, renamer: renamer, errorMapper: mapper)
        let applyResult = await BatchRenameAction.s214Apply(preview: preview, renamer: renamer, errorMapper: mapper)

        XCTAssertEqual(loadedPreview.applyReport, preview)
        XCTAssertEqual(applyResult.report, report)
        XCTAssertEqual(
            await renamer.previewRequests,
            [BatchRenamePreviewRequest(repoPath: "/repo", fileIDs: [11, 12], rule: rule)]
        )
        XCTAssertEqual(
            await renamer.applyRequests,
            [BatchRenameApplyRequest(repoPath: "/repo", fileIDs: [11, 12], rule: rule, token: "preview-token")]
        )
    }

    func testS214C210BatchRenameUsesCurrentListOrderForPreviewAndApply() async {
        let rule = BatchRenameRuleSnapshot.batchRenameRule(.keepBaseSequence, separator: "_", startNumber: 1, padding: 2)
        let preview = BatchRenamePreviewReportSnapshot.preview(rule: rule, token: "preview-token", fileIDs: [30, 10, 20])
        let renamer = BatchRenameRecordingRenamer(preview: .success(preview), apply: .success(.report()))
        let mapper = BatchRenameErrorMapper(mapping: .batchRenameConflict)

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
        XCTAssertEqual(await renamer.previewRequests.map(\.fileIDs), [[30, 10, 20]])
        XCTAssertEqual(await renamer.applyRequests.map(\.fileIDs), [[30, 10, 20]])
    }

    func testS214C210BatchRenameEntryUsesListOrderInsteadOfIDOrNameOrder() {
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

    func testS214C210BatchRenameActionMapsPreviewAndApplyErrors() async {
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
        let mapper = BatchRenameErrorMapper(mapping: .batchRenameConflict)

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
        XCTAssertEqual(await mapper.errors.count, 2)
    }
}

private struct RenameRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var newName: String
}

private actor RenameRecordingRenamer: CoreFileRenaming {
    private let result: Result<FileEntrySnapshot, Error>
    private var requests: [RenameRequest] = []

    init(result: Result<FileEntrySnapshot, Error>) {
        self.result = result
    }

    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        requests.append(RenameRequest(repoPath: repoPath, fileID: fileID, newName: newName))
        return try result.get()
    }

    func recordedRequests() -> [RenameRequest] {
        requests
    }
}

private extension FileEntrySnapshot {
    static func renameFixture(id: Int64, name: String, updatedAt: Int64 = 1_700_000_100) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/contracts/\(name)",
            originalName: "old.pdf",
            currentName: name,
            category: "docs",
            sizeBytes: 512,
            hashSha256: "rename-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: updatedAt
        )
    }
}

private extension RepositoryOpeningResult {
    static func renameFixture(
        repoPath: String,
        files: [FileEntrySnapshot],
        writeLockedFileIDs: Set<Int64> = []
    ) -> RepositoryOpeningResult {
        var opening = RepositoryOpeningResult.detailMetaFixture(repoPath: repoPath, files: files)
        opening.writeLockedFileIDs = writeLockedFileIDs
        return opening
    }
}

private extension CoreErrorMappingSnapshot {
    static func renameConflict() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .conflict,
            userMessage: "A file with this name already exists.",
            severity: .medium,
            suggestedAction: "Choose a different name, then retry.",
            recoverability: .userActionRequired,
            rawContext: "S1-33 C1-22 rename_file"
        )
    }
}

private extension BatchRenameValidation {
    static func s214CanApply(
        fileIDs: [Int64],
        preview: BatchRenamePreviewReportSnapshot?,
        rule: BatchRenameRuleSnapshot,
        disabledReason: String? = nil,
        isApplying: Bool = false
    ) -> Bool {
        canApply(
            fileIDs: fileIDs,
            preview: preview,
            rule: rule,
            disabledReason: disabledReason,
            isApplying: isApplying
        )
    }
}

private extension BatchRenameAction {
    static func s214Preview(
        rule: BatchRenameRuleSnapshot,
        renamer: any CoreBatchRenaming,
        errorMapper: any CoreErrorMapping
    ) async -> BatchRenamePreviewState {
        await preview(repoPath: "/repo", fileIDs: [11, 12], rule: rule, renamer: renamer, errorMapper: errorMapper)
    }

    static func s214Apply(
        preview: BatchRenamePreviewReportSnapshot,
        renamer: any CoreBatchRenaming,
        errorMapper: any CoreErrorMapping
    ) async -> BatchRenameApplyResult {
        await apply(repoPath: "/repo", fileIDs: [11, 12], preview: preview, renamer: renamer, errorMapper: errorMapper)
    }
}

private func makeRenameTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixRenameFile-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
