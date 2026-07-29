import Foundation

@MainActor
final class ImportBatchCopyImportModel: ObservableObject, ImportProgressQueueContinuing {
    @Published private(set) var rows: [ImportBatchCopyImportRow] = []
    @Published private(set) var status: ImportBatchCopyImportStatus = .idle
    @Published var selectedStorageMode: ImportSingleFileStorageMode = .copy
    @Published var selectedNamingStrategy: ImportBatchNamingStrategy = .suggestedName
    @Published private var namingPrefixOverride: String
    @Published var isICloudDownloading = false
    @Published private(set) var replaceConfirmationErrorMessage: LocalizedMessage?
    @Published private(set) var replaceConfirmationDiagnosticsMessage: LocalizedMessage?
    @Published var conflictBatchPreviewState: ImportConflictBatchPreviewState = .idle
    @Published var conflictBatchApplyResult: ImportConflictBatchApplyResult?
    @Published var conflictBatchUndoState: BatchTagUndoState = .idle
    @Published var isConflictBatchApplying = false
    @Published var conflictBatchDuplicateStrategy: ImportConflictBatchStrategySnapshot = .skip
    @Published var conflictBatchSameNameStrategy: ImportConflictBatchStrategySnapshot = .keepBoth
    @Published var appliesConflictBatchToAll = true
    @Published var selectedConflictBatchIDs: Set<String> = []
    @Published var isConflictBatchReplaceConfirmed = false
    @Published var conflictBatchPerItemQueue: ImportConflictBatchPerItemQueue?

    let importer: any CoreBatchCopyImporting
    let conflictBatcher: any CoreImportConflictBatching
    let undoActionStore: any CoreUndoActionLogging
    let sessionStore: any ImportBatchSessionPersisting
    let errorMapper: any CoreErrorMapping
    let placeholderDownloader: any ICloudPlaceholderDownloading
    var request: ImportEntryRequest?
    var selectedDestination: ImportBatchDestinationOption = .autoClassify
    private(set) var lastFailureMapping: CoreErrorMappingSnapshot?

    var namingPrefix: String {
        get { namingPrefixOverride }
        set { namingPrefixOverride = newValue }
    }

    init(
        importer: any CoreBatchCopyImporting,
        errorMapper: any CoreErrorMapping,
        conflictBatcher: any CoreImportConflictBatching = CoreBridge(),
        undoActionStore: any CoreUndoActionLogging = AppCoreServices.undoActionStore,
        sessionStore: any ImportBatchSessionPersisting = AppPlatformServices.importBatchSessionStore,
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader(),
        initialNamingPrefix: String? = nil
    ) {
        namingPrefixOverride = initialNamingPrefix ?? L10n.editableDefault("import.batch-naming.default-prefix")
        self.importer = importer
        self.conflictBatcher = conflictBatcher
        self.undoActionStore = undoActionStore
        self.sessionStore = sessionStore
        self.errorMapper = errorMapper
        self.placeholderDownloader = placeholderDownloader
    }
}

extension ImportBatchCopyImportModel {
    func retryReplaceConfirmation() {
        clearReplaceConfirmationRecovery()
    }

    func collectReplaceConfirmationDiagnostics() {
        replaceConfirmationDiagnosticsMessage = L10n.message("import.replace-confirmation.diagnostics-collected")
    }

    func clearReplaceConfirmationRecovery() {
        replaceConfirmationErrorMessage = nil
        replaceConfirmationDiagnosticsMessage = nil
    }

    func recordReplaceConfirmationFailure(_ message: LocalizedMessage) {
        replaceConfirmationErrorMessage = message
        replaceConfirmationDiagnosticsMessage = nil
    }

    func applyPreviewRows(
        _ previewRows: [ImportBatchPreviewRow],
        request: ImportEntryRequest?,
        selectedDestination: ImportBatchDestinationOption
    ) {
        let isNewRequest = self.request?.id != request?.id
        let duplicateStrategies = currentDuplicateStrategiesByRowID()
        let duplicateStatuses = currentDuplicateStatusesByRowID()
        let nameConflictResolutions = currentNameConflictResolutionsByRowID()
        let categoryOverrides = currentCategoryOverridesByRowID()
        rows = mapPreviewRows(previewRows, request: request)
            .map { applyNamingStrategy(to: $0) }
            .map { restoreCategoryOverride(for: $0, from: categoryOverrides) }
            .map { restoreDuplicateStatus(for: $0, from: duplicateStatuses) }
            .map { restoreDuplicateStrategy(for: $0, from: duplicateStrategies) }
            .map { restoreNameConflictResolution(for: $0, from: nameConflictResolutions) }
        self.request = request
        self.selectedDestination = selectedDestination
        if isNewRequest {
            selectedStorageMode = request?.defaultStorageMode ?? .copy
        }
        lastFailureMapping = nil
        clearReplaceConfirmationRecovery()
        if case .imported = status {
            return
        }
        if !status.isImporting {
            status = .idle
        }
    }

    func importReadyFiles(
        selectedDestination: ImportBatchDestinationOption,
        controlState: ImportProgressControlState? = nil,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void = { _ in }
    ) async -> ImportBatchImportResult? {
        guard let request else { return nil }
        guard importDisabledReason == nil else { return nil }
        self.selectedDestination = selectedDestination

        let readyRowIDs = Set(importableRows.map(\.id))
        let total = importableRows.count
        let initialPreviewErrorCount = previewErrorCount
        let actionContext = CoreImportTraceContext.operation(
            actionID: "repository.import.batch.confirmed",
            componentID: "macos.import.batch"
        )
        lastFailureMapping = nil
        await AppLogger.shared.recordUIAction(traceContext: actionContext)
        await saveImportSession(
            request: request,
            completed: 0,
            failed: 0,
            total: total,
            currentPath: currentImportPath ?? request.sheetTitle
        )
        let runState = await importReadyRows(
            input: ImportBatchCopyRunInput(
                readyRowIDs: readyRowIDs,
                request: request,
                selectedDestination: selectedDestination,
                total: total,
                traceID: actionContext.traceID
            ),
            controlState: controlState,
            reportProgress: reportProgress
        )

        if !runState.stoppedForDuplicate {
            markSkippedDuplicates()
            status = .imported(successful: runState.completed, failed: runState.failed)
        } else {
            status = .idle
        }
        if shouldClearImportSession(runState: runState, total: total) {
            await sessionStore.clearSession(repoPath: request.repoPath)
        }
        return importResult(
            runState: runState,
            initialPreviewErrorCount: initialPreviewErrorCount,
            total: total
        )
    }

    private func importResult(
        runState: ImportBatchCopyRunState,
        initialPreviewErrorCount: Int,
        total: Int
    ) -> ImportBatchImportResult {
        ImportBatchImportResult(
            succeededEntries: runState.succeededEntries,
            failedCount: runState.failed,
            previewErrorCount: initialPreviewErrorCount,
            total: total,
            lastImportedPath: runState.lastImportedPath,
            pendingDuplicateCount: unresolvedDuplicateCount,
            skippedDuplicateCount: skippedDuplicateCount,
            pendingICloudCount: pendingICloudCount,
            didStopAfterCurrentFile: runState.didStopAfterCurrentFile,
            fatalRetryContext: runState.fatalRetryContext
        )
    }

    private func importReadyRows(
        input: ImportBatchCopyRunInput,
        controlState: ImportProgressControlState?,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchCopyRunState {
        var state = ImportBatchCopyRunState()
        for index in rows.indices where input.readyRowIDs.contains(rows[index].id) {
            let traceContext = CoreImportTraceContext.operation(
                traceID: input.traceID,
                actionID: "repository.import.confirmed",
                componentID: "macos.import.batch"
            )
            let cycle = await runImportCycle(
                input: ImportBatchCopyCycleInput(
                    rowIndex: index,
                    request: input.request,
                    selectedDestination: input.selectedDestination,
                    completed: state.completed,
                    failed: state.failed,
                    total: input.total,
                    traceContext: traceContext
                ),
                reportProgress: reportProgress
            )
            updateImportRunState(
                &state,
                cycle: cycle,
                rowIndex: index,
                request: input.request,
                traceContext: traceContext
            )
            reportProgress(cycle.progress)
            if shouldStopImportRun(&state, controlState: controlState, reportProgress: reportProgress) {
                break
            }
        }
        return state
    }

    private func updateImportRunState(
        _ state: inout ImportBatchCopyRunState,
        cycle: ImportBatchCopyCycleResult,
        rowIndex: Int,
        request: ImportEntryRequest,
        traceContext: CoreImportTraceContext
    ) {
        state.completed = cycle.completed
        state.failed = cycle.failed
        state.lastImportedPath = cycle.lastImportedPath ?? state.lastImportedPath
        state.stoppedForDuplicate = cycle.stoppedForDuplicate
        if let entry = cycle.entry {
            state.succeededEntries.append(entry)
        }
        if cycle.stoppedForQueue {
            state.fatalRetryContext = retryContext(
                for: rows[rowIndex],
                request: request,
                traceContext: traceContext
            )
        }
    }

    private func shouldClearImportSession(runState: ImportBatchCopyRunState, total: Int) -> Bool {
        !runState.stoppedForDuplicate
            && (runState.didStopAfterCurrentFile || runState.completed + runState.failed >= total)
    }

    private func shouldStopImportRun(
        _ state: inout ImportBatchCopyRunState,
        controlState: ImportProgressControlState?,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) -> Bool {
        if state.stoppedForDuplicate || state.fatalRetryContext != nil { return true }
        guard controlState?.isStopAfterCurrentFileRequested == true else { return false }
        controlState?.markStoppedAfterCurrentFile()
        state.didStopAfterCurrentFile = true
        reportProgress(stoppedProgressSnapshot(currentPath: state.lastImportedPath))
        return true
    }

    func runImportCycle(
        input: ImportBatchCopyCycleInput,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchCopyCycleResult {
        let rowIndex = input.rowIndex
        let row = rows[rowIndex]
        let currentPath = targetRelativePath(for: row, destination: input.selectedDestination)
        beginImportCycle(
            at: rowIndex,
            completed: input.completed,
            failed: input.failed,
            total: input.total,
            currentPath: currentPath
        )
        reportProgress(ImportBatchProgressSnapshot(
            completed: input.completed,
            failed: input.failed,
            total: input.total,
            remaining: input.total - input.completed - input.failed,
            currentPath: currentPath
        ))

        do {
            return try await finishSuccessfulImportCycle(
                row,
                rowIndex: rowIndex,
                input: input,
                currentPath: currentPath
            )
        } catch {
            return await finishFailedImportCycle(error, rowIndex: rowIndex, input: input, currentPath: currentPath)
        }
    }

    private func finishSuccessfulImportCycle(
        _ row: ImportBatchCopyImportRow,
        rowIndex: Int,
        input: ImportBatchCopyCycleInput,
        currentPath: String
    ) async throws -> ImportBatchCopyCycleResult {
        let entry = try await importRow(
            row,
            request: input.request,
            selectedDestination: input.selectedDestination,
            traceContext: input.traceContext
        )
        rows[rowIndex].status = .imported
        rows[rowIndex].importCommitState = entry.importCommitState
        let result = ImportBatchCopyCycleResult.success(
            entry: entry,
            completed: input.completed + 1,
            failed: input.failed,
            total: input.total,
            currentPath: currentPath
        )
        await saveImportSession(from: result, request: input.request)
        return result
    }

    private func finishFailedImportCycle(
        _ error: Error,
        rowIndex: Int,
        input: ImportBatchCopyCycleInput,
        currentPath: String
    ) async -> ImportBatchCopyCycleResult {
        if handleDuplicateFile(error, at: rowIndex) {
            return .duplicate(
                completed: input.completed,
                failed: input.failed,
                total: input.total,
                currentPath: currentPath
            )
        }
        let mapping = await mapImportError(error)
        lastFailureMapping = mapping
        rows[rowIndex].status = .error(.localized(mapping.userMessageDescriptor))
        let result = ImportBatchCopyCycleResult.failure(
            completed: input.completed,
            failed: input.failed + 1,
            total: input.total,
            currentPath: currentPath,
            stoppedForQueue: mapping.recoverability == .fatal
        )
        await saveImportSession(from: result, request: input.request)
        return result
    }

    private func beginImportCycle(
        at rowIndex: Int,
        completed: Int,
        failed: Int,
        total: Int,
        currentPath: String
    ) {
        rows[rowIndex].status = .importing(selectedStorageMode)
        status = .importing(
            completed: completed,
            total: total,
            failed: failed,
            currentPath: currentPath
        )
    }

    func setStatus(_ status: ImportBatchCopyImportRowStatus, for rowID: ImportBatchCopyImportRow.ID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].status = status
    }

    func setImportCommitState(_ state: CoreImportCommitState, for rowID: ImportBatchCopyImportRow.ID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].importCommitState = state
    }

    func updateNamingStrategy(_ strategy: ImportBatchNamingStrategy) {
        selectedNamingStrategy = strategy
        rows = rows.map(applyNamingStrategy)
    }

    func updateCategoryOverride(for rowID: ImportBatchCopyImportRow.ID, category: String) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if shouldClearCategoryOverride(trimmedCategory, for: rows[index]) {
            rows[index].categoryOverride = nil
        } else {
            rows[index].categoryOverride = trimmedCategory
        }
    }

    func duplicateStrategy(for row: ImportBatchCopyImportRow) -> DuplicateStrategy {
        if let duplicateResolution = row.duplicateResolution {
            return duplicateResolution.duplicateStrategy
        }
        if let nameConflictResolution = row.nameConflictResolution {
            if nameConflictResolution.isReplace {
                return .overwrite
            }
            return .keepBoth
        }
        return .ask
    }

    private func handleDuplicateFile(_ error: Error, at rowIndex: Int) -> Bool {
        guard let context = CoreErrorRawContextSnapshot(error), context.kind == .duplicateFile else {
            return false
        }
        rows[rowIndex].status = .duplicate(existingPath: context.rawContext, strategy: .skip, isReplaceConfirmed: false)
        return true
    }

    func markSkippedDuplicates(excluding excludedIndex: Int? = nil) {
        for index in rows.indices where rows[index].duplicateResolution == .skip {
            guard index != excludedIndex else { continue }
            if case let .duplicate(existingPath, _, _) = rows[index].status {
                rows[index].status = .skippedDuplicate(existingPath: existingPath)
            }
        }
    }

    func clearLastFailureMapping() {
        lastFailureMapping = nil
    }

    func finishImportedStatus(successful: Int, failed: Int) {
        status = .imported(successful: successful, failed: failed)
    }
}
