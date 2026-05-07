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

    private let importer: any CoreBatchCopyImporting
    private let errorMapper: any CoreErrorMapping
    let placeholderDownloader: any ICloudPlaceholderDownloading
    var request: ImportEntryRequest?
    var selectedDestination: ImportBatchDestinationOption = .autoClassify
    private(set) var lastFailureMapping: CoreErrorMappingSnapshot?

    init(
        importer: any CoreBatchCopyImporting,
        errorMapper: any CoreErrorMapping,
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader()
    ) {
        self.importer = importer
        self.errorMapper = errorMapper
        self.placeholderDownloader = placeholderDownloader
    }

    var currentImportPath: String? {
        switch status {
        case .importing(_, _, _, let currentPath):
            return currentPath
        case .idle, .imported:
            return importableRows.first.map { targetRelativePath(for: $0, destination: selectedDestination) }
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

    var pendingICloudSummaryCount: Int { pendingICloudCount }

    var previewErrorCount: Int {
        rows.filter { row in
            if case .error = row.status { return true }
            return false
        }.count
    }

    var blockedCount: Int { rows.filter(\.isBlockedForImport).count }

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
            "No user file contents included.",
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

    var hasPendingDuplicateResolution: Bool { unresolvedDuplicateCount > 0 }

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
                return true
            case .loading, .ready, .duplicate, .nameConflict, .importing, .skippedDuplicate, .imported:
                return false
            }
        }
    }

    func applyPreviewRows(
        _ previewRows: [ImportBatchPreviewRow],
        request: ImportEntryRequest?,
        selectedDestination: ImportBatchDestinationOption
    ) {
        let duplicateStrategies = currentDuplicateStrategiesByRowID()
        let duplicateStatuses = currentDuplicateStatusesByRowID()
        let nameConflictResolutions = currentNameConflictResolutionsByRowID()
        let categoryOverrides = currentCategoryOverridesByRowID()
        self.rows = mapPreviewRows(previewRows, request: request)
            .map { applyNamingStrategy(to: $0) }
            .map { restoreCategoryOverride(for: $0, from: categoryOverrides) }
            .map { restoreDuplicateStatus(for: $0, from: duplicateStatuses) }
            .map { restoreDuplicateStrategy(for: $0, from: duplicateStrategies) }
            .map { restoreNameConflictResolution(for: $0, from: nameConflictResolutions) }
        self.request = request
        self.selectedDestination = selectedDestination
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
        var completed = 0
        var failed = 0
        var succeededEntries: [FileEntrySnapshot] = []
        var lastImportedPath = ""
        var stoppedForDuplicate = false
        var didStopAfterCurrentFile = false
        var fatalRetryContext: ImportProgressRetryContext?
        lastFailureMapping = nil

        for index in rows.indices where readyRowIDs.contains(rows[index].id) {
            let cycle = await runImportCycle(
                at: index,
                request: request,
                selectedDestination: selectedDestination,
                completed: completed,
                failed: failed,
                total: total,
                reportProgress: reportProgress
            )
            completed = cycle.completed
            failed = cycle.failed
            lastImportedPath = cycle.lastImportedPath ?? lastImportedPath
            stoppedForDuplicate = cycle.stoppedForDuplicate
            if let entry = cycle.entry {
                succeededEntries.append(entry)
            }
            reportProgress(cycle.progress)
            if stoppedForDuplicate {
                break
            }
            if cycle.stoppedForQueue {
                fatalRetryContext = retryContext(for: rows[index], request: request)
                break
            }
            if controlState?.isStopAfterCurrentFileRequested == true {
                controlState?.markStoppedAfterCurrentFile()
                didStopAfterCurrentFile = true
                reportProgress(stoppedProgressSnapshot(currentPath: lastImportedPath))
                break
            }
        }

        if !stoppedForDuplicate {
            markSkippedDuplicates()
            status = .imported(successful: completed, failed: failed)
        } else {
            status = .idle
        }
        return ImportBatchImportResult(
            succeededEntries: succeededEntries,
            failedCount: failed,
            previewErrorCount: initialPreviewErrorCount,
            total: total,
            lastImportedPath: lastImportedPath,
            pendingDuplicateCount: unresolvedDuplicateCount,
            skippedDuplicateCount: skippedDuplicateCount,
            pendingICloudCount: pendingICloudCount,
            didStopAfterCurrentFile: didStopAfterCurrentFile,
            fatalRetryContext: fatalRetryContext
        )
    }

    func runImportCycle(
        at rowIndex: Int,
        request: ImportEntryRequest,
        selectedDestination: ImportBatchDestinationOption,
        completed: Int,
        failed: Int,
        total: Int,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void
    ) async -> ImportBatchCopyCycleResult {
        let row = rows[rowIndex]
        let currentPath = targetRelativePath(for: row, destination: selectedDestination)
        beginImportCycle(
            at: rowIndex,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath
        )
        reportProgress(ImportBatchProgressSnapshot(
            completed: completed,
            failed: failed,
            total: total,
            remaining: total - completed - failed,
            currentPath: currentPath
        ))

        do {
            let entry = try await importRow(
                row,
                request: request,
                selectedDestination: selectedDestination
            )
            rows[rowIndex].status = .imported
            return .success(
                entry: entry,
                completed: completed + 1,
                failed: failed,
                total: total,
                currentPath: currentPath
            )
        } catch {
            if handleDuplicateFile(error, at: rowIndex) {
                return .duplicate(
                    completed: completed,
                    failed: failed,
                    total: total,
                    currentPath: currentPath
                )
            }
            let mapping = await mapImportError(error)
            lastFailureMapping = mapping
            rows[rowIndex].status = .error(mapping.userMessage)
            return .failure(
                completed: completed,
                failed: failed + 1,
                total: total,
                currentPath: currentPath,
                stoppedForQueue: mapping.recoverability == .fatal
            )
        }
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

    private func importRow(
        _ row: ImportBatchCopyImportRow,
        request: ImportEntryRequest,
        selectedDestination: ImportBatchDestinationOption
    ) async throws -> FileEntrySnapshot {
        try await importer.importBatchFile(
            repoPath: request.repoPath,
            sourceURL: row.sourceURL,
            storageMode: selectedStorageMode,
            destination: entryDestination(for: row, selectedDestination: selectedDestination),
            suggestedCategory: row.categoryOverride ?? row.predictedCategory,
            overrideFilename: row.resolvedIncomingName,
            duplicateStrategy: duplicateStrategy(for: row)
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

    private func mapImportError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func currentDuplicateStrategiesByRowID() -> [ImportBatchCopyImportRow.ID: ImportBatchDuplicateResolutionStrategy] {
        rows.reduce(into: [:]) { strategies, row in
            guard let strategy = row.duplicateResolution else { return }
            strategies[row.id] = strategy
        }
    }

    private func currentDuplicateStatusesByRowID() -> [ImportBatchCopyImportRow.ID: String] {
        rows.reduce(into: [:]) { duplicates, row in
            guard case .duplicate(let existingPath, _, _) = row.status else { return }
            duplicates[row.id] = existingPath
        }
    }

    private func currentNameConflictResolutionsByRowID()
        -> [ImportBatchCopyImportRow.ID: ImportBatchNameConflictResolution]
    {
        rows.reduce(into: [:]) { resolutions, row in
            guard case .nameConflict(_, let resolution) = row.status else { return }
            resolutions[row.id] = resolution
        }
    }

    private func restoreDuplicateStatus(
        for row: ImportBatchCopyImportRow,
        from duplicateStatuses: [ImportBatchCopyImportRow.ID: String]
    ) -> ImportBatchCopyImportRow {
        guard let existingPath = duplicateStatuses[row.id] else { return row }
        guard case .ready = row.status else { return row }
        var restoredRow = row
        restoredRow.status = .duplicate(existingPath: existingPath, strategy: .skip, isReplaceConfirmed: false)
        return restoredRow
    }
    private func restoreDuplicateStrategy(
        for row: ImportBatchCopyImportRow,
        from strategies: [ImportBatchCopyImportRow.ID: ImportBatchDuplicateResolutionStrategy]
    ) -> ImportBatchCopyImportRow {
        guard let strategy = strategies[row.id] else { return row }
        guard case .duplicate(let existingPath, _, let isReplaceConfirmed) = row.status else { return row }
        var restoredRow = row
        restoredRow.status = .duplicate(
            existingPath: existingPath,
            strategy: strategy,
            isReplaceConfirmed: strategy == .replace ? isReplaceConfirmed : false
        )
        return restoredRow
    }
    private func restoreNameConflictResolution(
        for row: ImportBatchCopyImportRow,
        from resolutions: [ImportBatchCopyImportRow.ID: ImportBatchNameConflictResolution]
    ) -> ImportBatchCopyImportRow {
        guard let resolution = resolutions[row.id] else { return row }
        guard case .nameConflict(let existingPath, _) = row.status else { return row }
        var restoredRow = row
        restoredRow.status = .nameConflict(existingPath: existingPath, resolution: resolution)
        return restoredRow
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
        guard case .DuplicateFile(let existingPath) = coreError else { return false }
        rows[rowIndex].status = .duplicate(existingPath: existingPath, strategy: .skip, isReplaceConfirmed: false)
        return true
    }

    func markSkippedDuplicates(excluding excludedIndex: Int? = nil) {
        for index in rows.indices where rows[index].duplicateResolution == .skip {
            guard index != excludedIndex else { continue }
            if case .duplicate(let existingPath, _, _) = rows[index].status {
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
