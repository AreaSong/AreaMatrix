import Foundation

@MainActor
final class ImportBatchCopyImportModel: ObservableObject, ImportProgressQueueContinuing {
    @Published private(set) var rows: [ImportBatchCopyImportRow] = []
    @Published private(set) var status: ImportBatchCopyImportStatus = .idle
    @Published var selectedStorageMode: ImportSingleFileStorageMode = .copy
    @Published var selectedNamingStrategy: ImportBatchNamingStrategy = .suggestedName
    @Published var namingPrefix = "Import"
    @Published var isICloudDownloading = false
    @Published private(set) var replaceConfirmationErrorMessage: String?
    @Published private(set) var replaceConfirmationDiagnosticsMessage: String?

    let importer: any CoreBatchCopyImporting
    let sessionStore: any ImportBatchSessionPersisting
    let errorMapper: any CoreErrorMapping
    let placeholderDownloader: any ICloudPlaceholderDownloading
    var request: ImportEntryRequest?
    var selectedDestination: ImportBatchDestinationOption = .autoClassify
    private(set) var lastFailureMapping: CoreErrorMappingSnapshot?

    init(
        importer: any CoreBatchCopyImporting,
        errorMapper: any CoreErrorMapping,
        sessionStore: any ImportBatchSessionPersisting = FileImportBatchSessionStore(),
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader()
    ) {
        self.importer = importer
        self.sessionStore = sessionStore
        self.errorMapper = errorMapper
        self.placeholderDownloader = placeholderDownloader
    }
}

extension ImportBatchCopyImportModel {
    var currentImportPath: String? {
        switch status {
        case let .importing(_, _, _, currentPath):
            currentPath
        case .idle, .imported:
            importableRows.first.map { targetRelativePath(for: $0, destination: selectedDestination) }
        }
    }

    var importDisabledReason: String? {
        if status.isImporting {
            return selectedStorageMode.importingBlockingMessage
        }
        if isICloudDownloading {
            return "正在下载 iCloud 文件"
        }
        if blockedCount > 0 {
            return "存在 BLOCKED 项，请先完成冲突处理"
        }
        if isAllRowsUnavailable {
            return "没有可导入的批量项目"
        }
        if !hasActionableRows {
            return "没有可导入或可跳过的批量项目"
        }
        return nil
    }

    var importableRows: [ImportBatchCopyImportRow] {
        rows.filter { row in
            if row.status.isReady { return true }
            return row.duplicateResolution?.importsIncomingFile == true
                || row.nameConflictResolution?.importsIncomingFile == true
        }
    }

    var skippedDuplicateCount: Int {
        rows.filter { row in
            if case .skippedDuplicate = row.status { return true }
            if row.duplicateResolution == .skip { return true }
            return false
        }.count
    }

    private var hasActionableRows: Bool {
        !importableRows.isEmpty
            || rows.contains { $0.duplicateResolution == .skip }
            || rows.contains { if case .iCloudPlaceholder = $0.status { return true }; return false }
    }

    var duplicateCount: Int {
        rows.filter { row in
            if case .duplicate = row.status { return true }
            if case .skippedDuplicate = row.status { return true }
            return false
        }.count
    }

    var nameConflictCount: Int {
        rows.filter { row in
            if case .nameConflict = row.status { return true }
            return false
        }.count
    }

    var iCloudPlaceholderCount: Int {
        rows.filter { row in
            if case .iCloudPlaceholder = row.status { return true }
            return false
        }.count
    }

    var pendingICloudSummaryCount: Int {
        pendingICloudCount
    }

    var previewErrorCount: Int {
        rows.filter { row in
            if case .error = row.status { return true }
            return false
        }.count
    }

    var blockedCount: Int {
        rows.filter(\.isBlockedForImport).count
    }

    var replaceOptionVisibility: ImportSingleFileReplaceOptionVisibility {
        guard request?.allowReplaceDuringImport == true else { return .hidden }
        return request?.isTrashAvailable == true ? .enabled : .disabled
    }

    func retryReplaceConfirmation() {
        clearReplaceConfirmationRecovery()
    }

    func collectReplaceConfirmationDiagnostics() {
        replaceConfirmationDiagnosticsMessage = [
            "Diagnostics collected for replace confirmation state.",
            "No user file contents included."
        ].joined(separator: " ")
    }

    func clearReplaceConfirmationRecovery() {
        replaceConfirmationErrorMessage = nil
        replaceConfirmationDiagnosticsMessage = nil
    }

    func recordReplaceConfirmationFailure(_ message: String) {
        replaceConfirmationErrorMessage = message
        replaceConfirmationDiagnosticsMessage = nil
    }

    var hasPendingDuplicateResolution: Bool {
        unresolvedDuplicateCount > 0
    }

    var unresolvedDuplicateCount: Int {
        rows.filter { row in
            if case .duplicate = row.status { return true }
            return false
        }.count
    }

    private var isAllRowsUnavailable: Bool {
        !rows.isEmpty && importableRows.isEmpty && rows.allSatisfy { row in
            switch row.status {
            case .error, .blocked, .iCloudPlaceholder, .skippedICloud:
                true
            case .loading, .ready, .duplicate, .nameConflict, .importing, .skippedDuplicate, .imported:
                false
            }
        }
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
        lastFailureMapping = nil
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
                total: total
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
        return ImportBatchImportResult(
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
            let cycle = await runImportCycle(
                input: ImportBatchCopyCycleInput(
                    rowIndex: index,
                    request: input.request,
                    selectedDestination: input.selectedDestination,
                    completed: state.completed,
                    failed: state.failed,
                    total: input.total
                ),
                reportProgress: reportProgress
            )
            updateImportRunState(&state, cycle: cycle, rowIndex: index, request: input.request)
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
        request: ImportEntryRequest
    ) {
        state.completed = cycle.completed
        state.failed = cycle.failed
        state.lastImportedPath = cycle.lastImportedPath ?? state.lastImportedPath
        state.stoppedForDuplicate = cycle.stoppedForDuplicate
        if let entry = cycle.entry {
            state.succeededEntries.append(entry)
        }
        if cycle.stoppedForQueue {
            state.fatalRetryContext = retryContext(for: rows[rowIndex], request: request)
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
            selectedDestination: input.selectedDestination
        )
        rows[rowIndex].status = .imported
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
        rows[rowIndex].status = .error(mapping.userMessage)
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
        guard let coreError = error as? CoreError else { return false }
        guard case let .DuplicateFile(existingPath) = coreError else { return false }
        rows[rowIndex].status = .duplicate(existingPath: existingPath, strategy: .skip, isReplaceConfirmed: false)
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
