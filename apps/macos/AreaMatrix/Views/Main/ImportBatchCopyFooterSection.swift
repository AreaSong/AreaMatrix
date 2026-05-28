import SwiftUI

struct RedoFeedbackRegion: View {
    let state: RedoActionState
    let sourceUndoAction: UndoActionRecordSnapshot?
    let onRedo: (RedoActionRecordSnapshot) -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            Label("Checking redo...", systemImage: "arrow.uturn.forward.circle")
                .accessibilityIdentifier("S2-22-C2-18-redo-checking")
        case let .available(action):
            redoSummary(action, status: "Available")
            Button("Redo") { onRedo(action) }
                .accessibilityIdentifier("S2-22-C2-18-redo-action")
        case let .disabled(action, reason):
            redoSummary(action, status: reason)
            Button("Redo") {}
                .disabled(true)
                .accessibilityIdentifier("S2-22-C2-18-redo-action-disabled")
        case let .unavailable(reason):
            Label(reason, systemImage: "arrow.uturn.forward.circle")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("S2-22-C2-18-redo-unavailable")
        case let .redoing(action):
            redoSummary(action, status: "Redoing...")
            Button("Redoing...") {}
                .disabled(true)
                .accessibilityIdentifier("S2-22-C2-18-redo-action-busy")
        case let .redone(result):
            Label(result.summary, systemImage: "checkmark.circle")
                .accessibilityIdentifier("S2-22-C2-18-redo-completed")
        case let .failed(mapping, action):
            VStack(alignment: .leading, spacing: 3) {
                Label("Could not redo action", systemImage: "exclamationmark.triangle")
                Text(mapping.userMessage)
                    .foregroundStyle(.secondary)
                if let action {
                    Text("Redo row retained: \(action.summary)")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("S2-22-C2-18-redo-failed")
        }
    }

    private func redoSummary(_ action: RedoActionRecordSnapshot, status: String) -> some View {
        let source = RedoUndoSourcePresentation(redoAction: action, undoActions: sourceUndoAction.map { [$0] } ?? [])
        return VStack(alignment: .leading, spacing: 3) {
            Label(action.summary, systemImage: "arrow.uturn.forward.circle")
            Text("\(status) · \(action.affectedCount) affected · \(source.sourceText)")
                .foregroundStyle(.secondary)
        }
    }
}

extension MainRepositoryContentView {
    var batchTagUndoToastOverlay: some View {
        BatchTagUndoToastHost(
            repoPath: opening.config.repoPath,
            undoStore: fileListModel.undoActionStore,
            redoStore: fileListModel.redoActionStore,
            errorMapper: fileListModel.errorMapper,
            onRefreshSelection: { Task { await fileListModel.retrySelectedFileDetail() } },
            onRefreshChangeLog: { Task { await fileListModel.loadSelectedFileChangeLog() } },
            onRefreshCurrentList: { Task { await fileListModel.retryCurrentCategory() } },
            onOpenHistory: { pendingUndoHistoryRequest = $0 },
            undoState: $batchTagUndoState,
            actionLogRefreshFailure: $batchTagActionLogRefreshFailure
        )
    }

    func undoHistorySheet(_ request: UndoToastHistoryRequest) -> some View {
        UndoHistoryPanel(
            repoPath: opening.config.repoPath,
            focusedActionID: request.focusedActionID,
            initialFailure: request.failureMapping,
            undoStore: fileListModel.undoActionStore,
            redoStore: fileListModel.redoActionStore,
            errorMapper: fileListModel.errorMapper,
            onClose: { pendingUndoHistoryRequest = nil },
            onUndoCompleted: handleUndoHistoryResult,
            onRedoCompleted: handleRedoHistoryResult
        )
    }

    func handleUndoHistoryResult(_ result: UndoActionResultSnapshot) {
        refreshAfterUndoRedo(targets: result.refreshTargets)
    }

    func handleRedoHistoryResult(_ result: RedoActionResultSnapshot) {
        refreshAfterUndoRedo(targets: result.refreshTargets)
    }

    func updateBatchTagUndoState(_ state: BatchTagUndoState) {
        batchTagUndoState = state
        batchTagActionLogRefreshFailure = nil
    }

    @MainActor
    func refreshLatestUndoToast() {
        Task {
            batchTagUndoState = await BatchTagUndoAction.refreshLatestToastState(
                repoPath: opening.config.repoPath,
                undoStore: fileListModel.undoActionStore,
                errorMapper: fileListModel.errorMapper
            )
            batchTagActionLogRefreshFailure = nil
        }
    }

    func openUndoHistoryFromToolbar() {
        pendingUndoHistoryRequest = UndoToastHistoryRequest(
            source: .viewHistory,
            state: batchTagUndoState,
            actionLogRefreshFailure: batchTagActionLogRefreshFailure
        )
    }

    func openUndoHistoryFromMenu() {
        pendingUndoHistoryRequest = UndoHistoryActionLog.menuRequest(
            state: batchTagUndoState,
            failure: batchTagActionLogRefreshFailure
        )
    }

    func openUndoHistoryFromShortcut() {
        pendingUndoHistoryRequest = UndoHistoryActionLog.shortcutRequest(
            state: batchTagUndoState,
            failure: batchTagActionLogRefreshFailure
        )
    }

    func openUndoHistoryFromRedoShortcut() {
        Task { await executeLatestRedoAction(entryPoint: .keyboardShortcut) }
    }

    @MainActor
    func executeLatestRedoAction(entryPoint: RedoLatestEntryPoint) async {
        if entryPoint == .commandPalette {
            fileListModel.commandPaletteState = .loading(commandPaletteContext())
        }
        let loaded = await UndoHistoryActionLog.load(
            repoPath: opening.config.repoPath,
            undoStore: fileListModel.undoActionStore,
            redoStore: fileListModel.redoActionStore,
            errorMapper: fileListModel.errorMapper
        )
        guard case let .loaded(snapshot) = loaded else {
            handleRedoEntryFailure(loaded.failure, entryPoint: entryPoint)
            return
        }
        let result = await UndoHistoryActionLog.redoLatest(
            repoPath: opening.config.repoPath,
            snapshot: snapshot,
            undoStore: fileListModel.undoActionStore,
            redoStore: fileListModel.redoActionStore,
            errorMapper: fileListModel.errorMapper
        )
        handleRedoEntryResult(result, entryPoint: entryPoint)
    }

    @MainActor
    private func handleRedoEntryResult(_ state: UndoHistoryState, entryPoint: RedoLatestEntryPoint) {
        switch state {
        case let .redone(result, _):
            closeCommandPaletteIfNeeded(entryPoint)
            handleRedoHistoryResult(result)
        case let .redoFailed(mapping, _, _), let .refreshFailed(mapping, _):
            handleRedoEntryFailure(mapping, entryPoint: entryPoint)
        case .loaded:
            handleRedoEntryFailure(RedoLatestEntryPoint.noRedoMapping, entryPoint: entryPoint)
        case let .failed(mapping):
            handleRedoEntryFailure(mapping, entryPoint: entryPoint)
        case .loading, .undoing, .undoFailed, .undone, .redoing:
            break
        }
    }

    @MainActor
    private func handleRedoEntryFailure(_ mapping: CoreErrorMappingSnapshot?, entryPoint: RedoLatestEntryPoint) {
        let mapping = mapping ?? RedoLatestEntryPoint.noRedoMapping
        switch entryPoint {
        case .commandPalette:
            fileListModel.commandPaletteState = .failed(
                commandPaletteContext(),
                fileListModel.commandPaletteState.snapshot ?? .commandRegistryRecovery(
                    query: fileListModel.commandPaletteQuery
                ),
                mapping
            )
        case .keyboardShortcut:
            batchTagActionLogRefreshFailure = mapping
            pendingUndoHistoryRequest = UndoHistoryActionLog.redoShortcutRequest(
                state: batchTagUndoState,
                failure: mapping
            )
        }
    }

    @MainActor
    private func closeCommandPaletteIfNeeded(_ entryPoint: RedoLatestEntryPoint) {
        guard entryPoint == .commandPalette else { return }
        closeCommandPalette()
    }

    private func refreshAfterUndoRedo(targets: [String]) {
        let plan = BatchTagUndoRefreshPlan(refreshTargets: targets)
        if plan.refreshesCurrentList {
            Task { await fileListModel.retryCurrentCategory() }
        }
        if plan.refreshesSelectionDetails {
            Task { await fileListModel.retrySelectedFileDetail() }
        }
        if plan.refreshesChangeLog {
            Task { await fileListModel.loadSelectedFileChangeLog() }
        }
        if plan.refreshesUndoActions {
            refreshLatestUndoToast()
        }
    }
}

enum RedoLatestEntryPoint: Equatable {
    case keyboardShortcut
    case commandPalette

    static let noRedoMapping = CoreErrorMappingSnapshot(
        kind: .expiredAction,
        userMessage: "No redoable action is available.",
        severity: .medium,
        suggestedAction: "Undo an AreaMatrix action before using Redo latest.",
        recoverability: .refreshRequired,
        rawContext: "S2-22 C2-18 redo-action-log"
    )
}

struct ImportBatchCopyFooterSection: View {
    let request: ImportEntryRequest
    @ObservedObject var batchPreviewModel: ImportBatchPreviewModel
    @ObservedObject var batchImportModel: ImportBatchCopyImportModel
    let onCancel: () -> Void
    let onImportProgress: ImportBatchProgressHandler
    let onImportFailed: ImportBatchFailureHandler
    let onImportResults: ImportBatchProgressHandler
    let importProgressControlState: ImportProgressControlState
    let onImported: (String, FileEntrySnapshot) -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Import") {
                Task { await importBatch() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(importButtonDisabled)
            .help(importButtonHelp)
        }
    }

    private var importButtonDisabled: Bool {
        if batchPreviewModel.status.isLoading {
            return true
        }
        return batchPreviewModel.importDisabledReason != nil || batchImportModel.importDisabledReason != nil
    }

    private var importButtonHelp: String {
        if batchPreviewModel.status.isLoading {
            return "Preparing preview..."
        }
        return batchPreviewModel.importDisabledReason ?? batchImportModel.importDisabledReason ?? ""
    }

    @MainActor
    private func importBatch() async {
        prepareImport()
        importProgressControlState.reset()
        if let initialProgress = initialProgressSnapshot() {
            onImportProgress(initialProgress)
        }
        var lastProgress: ImportBatchProgressSnapshot?
        let outcome = await batchImportModel.importReadyFiles(
            selectedDestination: batchPreviewModel.selectedDestination,
            controlState: importProgressControlState
        ) { progress in
            let progressWithItems = progress.withItems(batchImportModel.progressItems())
            lastProgress = progressWithItems
            onImportProgress(progressWithItems)
        }

        guard let outcome else { return }
        if outcome.didStopAfterCurrentFile {
            onImportResults(
                outcome.progressSnapshot(currentPath: batchImportModel.currentImportPath ?? request.sheetTitle)
                    .withItems(batchImportModel.progressItems())
            )
            return
        }
        if outcome.pendingDuplicateCount > 0 {
            return
        }
        if let retryContext = outcome.fatalRetryContext,
           let failure = batchImportModel.lastFailureMapping,
           let progress = lastProgress {
            onImportFailed(progress, failure, retryContext, .checking)
            importProgressControlState.registerQueueContinuation(batchImportModel)
            return
        }
        if outcome.needsResultSummary {
            onImportResults(
                outcome.progressSnapshot(currentPath: batchImportModel.currentImportPath ?? request.sheetTitle)
                    .withItems(batchImportModel.progressItems())
            )
            return
        }
        guard outcome.failedCount == 0 else {
            return
        }

        guard let importedEntry = outcome.succeededEntries.last else {
            onCancel()
            return
        }

        onImported(request.repoPath, importedEntry)
    }

    @MainActor
    private func prepareImport() {
        guard !batchImportModel.hasPendingDuplicateResolution else { return }
        batchImportModel.applyPreviewRows(
            batchPreviewModel.rows,
            request: request,
            selectedDestination: batchPreviewModel.selectedDestination
        )
    }

    private func initialProgressSnapshot() -> ImportBatchProgressSnapshot? {
        guard batchImportModel.importDisabledReason == nil else { return nil }
        let total = batchImportModel.importableRows.count
        guard total > 0 else { return nil }
        return ImportBatchProgressSnapshot(
            completed: 0,
            failed: 0,
            total: total,
            remaining: total,
            currentPath: batchImportModel.currentImportPath ?? request.sheetTitle,
            items: batchImportModel.progressItems()
        )
    }
}

struct ImportBatchSummarySection: View {
    let totalSizeDescription: String?
    let sourceLabel: String
    let duplicateCount: Int
    let nameConflictCount: Int
    let iCloudPlaceholderCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("批量导入摘要")
                .font(.headline)
            HStack(spacing: 16) {
                if let totalSizeDescription {
                    LabeledContent("总大小", value: totalSizeDescription)
                }
                LabeledContent("来源", value: sourceLabel)
                LabeledContent("预计重复", value: "\(duplicateCount) 个")
                LabeledContent("重名冲突", value: "\(nameConflictCount) 个")
                LabeledContent("iCloud", value: "\(iCloudPlaceholderCount) 个")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}

struct ImportConflictBatchUndoStateView: View {
    let state: BatchTagUndoState
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case let .loading(token):
            undoStatus("Loading Undo action \(token)...")
        case let .ready(action):
            HStack(spacing: 8) {
                undoStatus(action.summary)
                Button("Undo", action: onUndo)
                    .keyboardShortcut("z", modifiers: [.command])
            }
            .accessibilityLabel("Undo available. \(action.summary)")
        case let .disabled(action, reason):
            undoStatus("\(action.summary) \(reason)")
        case let .unavailable(reason):
            undoStatus(reason)
        case let .undoing(action):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                undoStatus("Undoing \(action.summary)")
            }
        case let .undone(result):
            HStack(spacing: 8) {
                undoStatus(result.summary)
                Button("Dismiss", action: onDismiss)
            }
            .accessibilityLabel("Undo completed. \(result.summary)")
        case let .failed(mapping, previous):
            HStack(spacing: 8) {
                undoStatus(mapping.userMessage)
                    .foregroundStyle(.red)
                if previous != nil {
                    Button("Dismiss", action: onDismiss)
                }
            }
            .accessibilityLabel("Undo failed. \(mapping.userMessage)")
        }
    }

    private func undoStatus(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
