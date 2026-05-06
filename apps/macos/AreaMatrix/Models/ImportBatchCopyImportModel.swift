import Foundation

@MainActor
final class ImportBatchCopyImportModel: ObservableObject {
    @Published private(set) var rows: [ImportBatchCopyImportRow] = []
    @Published private(set) var status: ImportBatchCopyImportStatus = .idle

    private let importer: any CoreBatchCopyImporting
    private let errorMapper: any CoreErrorMapping
    private var request: ImportEntryRequest?
    private var selectedDestination: ImportBatchDestinationOption = .autoClassify
    private(set) var lastFailureMapping: CoreErrorMappingSnapshot?

    init(
        importer: any CoreBatchCopyImporting,
        errorMapper: any CoreErrorMapping
    ) {
        self.importer = importer
        self.errorMapper = errorMapper
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
            return "正在复制导入"
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
        !importableRows.isEmpty || rows.contains { $0.duplicateResolution == .skip }
    }

    var duplicateCount: Int {
        rows.filter { row in
            if case .duplicate = row.status { return true }
            if case .skippedDuplicate = row.status { return true }
            return false
        }.count
    }

    var hasPendingDuplicateResolution: Bool {
        unresolvedDuplicateCount > 0
    }

    private var unresolvedDuplicateCount: Int {
        rows.filter { row in
            if case .duplicate = row.status { return true }
            return false
        }.count
    }

    func applyPreviewRows(
        _ previewRows: [ImportBatchPreviewRow],
        request: ImportEntryRequest?,
        selectedDestination: ImportBatchDestinationOption
    ) {
        let duplicateStrategies = currentDuplicateStrategiesByRowID()
        let duplicateStatuses = currentDuplicateStatusesByRowID()
        self.rows = mapPreviewRows(previewRows, request: request)
            .map { restoreDuplicateStatus(for: $0, from: duplicateStatuses) }
            .map { restoreDuplicateStrategy(for: $0, from: duplicateStrategies) }
        self.request = request
        self.selectedDestination = selectedDestination
        lastFailureMapping = nil
        if case .imported = status {
            return
        }
        if !status.isImporting {
            status = .idle
        }
    }

    func importReadyFiles(
        selectedDestination: ImportBatchDestinationOption,
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void = { _ in }
    ) async -> ImportBatchImportResult? {
        guard let request else { return nil }
        guard importDisabledReason == nil else { return nil }
        self.selectedDestination = selectedDestination

        let readyRowIDs = Set(importableRows.map(\.id))
        let total = importableRows.count
        var completed = 0
        var failed = 0
        var succeededEntries: [FileEntrySnapshot] = []
        var lastImportedPath = ""
        var stoppedForDuplicate = false
        lastFailureMapping = nil

        for index in rows.indices where readyRowIDs.contains(rows[index].id) {
            let cycle = await runImportCycle(
                at: index,
                request: request,
                selectedDestination: selectedDestination,
                completed: completed,
                failed: failed,
                total: total
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
            total: total,
            lastImportedPath: lastImportedPath,
            pendingDuplicateCount: unresolvedDuplicateCount
        )
    }

    private func runImportCycle(
        at rowIndex: Int,
        request: ImportEntryRequest,
        selectedDestination: ImportBatchDestinationOption,
        completed: Int,
        failed: Int,
        total: Int
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
                currentPath: currentPath
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
        rows[rowIndex].status = .importing
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
        try await importer.importCopiedFile(
            repoPath: request.repoPath,
            sourceURL: row.sourceURL,
            destination: selectedDestination.entryDestination,
            suggestedCategory: row.predictedCategory,
            overrideFilename: row.suggestedName,
            duplicateStrategy: duplicateStrategy(for: row)
        )
    }

    func updateDuplicateStrategy(
        for rowID: ImportBatchCopyImportRow.ID,
        strategy: ImportBatchDuplicateResolutionStrategy
    ) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        guard case .duplicate(let existingPath, _) = rows[index].status else { return }
        rows[index].status = .duplicate(existingPath: existingPath, strategy: strategy)
    }

    private func targetRelativePath(
        for row: ImportBatchCopyImportRow,
        destination: ImportBatchDestinationOption
    ) -> String {
        let filename = row.suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch destination {
        case .autoClassify:
            let category = (row.predictedCategory ?? "inbox").trimmingCharacters(in: .whitespacesAndNewlines)
            return category.isEmpty ? filename : "\(category)/\(filename)"
        case .category(let slug):
            return "\(slug)/\(filename)"
        case .repositoryRoot:
            return filename
        }
    }

    private func mapImportError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func mapPreviewRows(
        _ previewRows: [ImportBatchPreviewRow],
        request: ImportEntryRequest?
    ) -> [ImportBatchCopyImportRow] {
        guard let request else { return [] }

        return previewRows.compactMap { row in
            guard let sourceURL = sourceURL(for: row, request: request) else { return nil }
            return ImportBatchCopyImportRow(
                originalName: row.originalName,
                sourcePath: row.sourcePath,
                sourceURL: sourceURL,
                sizeBytes: row.sizeBytes,
                predictedCategory: row.predictedCategory,
                suggestedName: row.suggestedName,
                status: copyStatus(from: row.status)
            )
        }
    }

    private func sourceURL(
        for row: ImportBatchPreviewRow,
        request: ImportEntryRequest
    ) -> URL? {
        request.urls.first { url in
            (url.path as NSString).abbreviatingWithTildeInPath == row.sourcePath
        }
    }

    private func copyStatus(from previewStatus: ImportBatchPreviewRowStatus) -> ImportBatchCopyImportRowStatus {
        switch previewStatus {
        case .loading:
            return .loading
        case .ready(let reasonLabel):
            return .ready(reasonLabel: reasonLabel)
        case .duplicate(let existingPath, _):
            return .duplicate(existingPath: existingPath, strategy: .skip)
        case .error(let message):
            return .error(message)
        }
    }

    private func currentDuplicateStrategiesByRowID() -> [ImportBatchCopyImportRow.ID: ImportBatchDuplicateResolutionStrategy] {
        rows.reduce(into: [:]) { strategies, row in
            guard let strategy = row.duplicateResolution else { return }
            strategies[row.id] = strategy
        }
    }

    private func currentDuplicateStatusesByRowID() -> [ImportBatchCopyImportRow.ID: String] {
        rows.reduce(into: [:]) { duplicates, row in
            guard case .duplicate(let existingPath, _) = row.status else { return }
            duplicates[row.id] = existingPath
        }
    }

    private func restoreDuplicateStatus(
        for row: ImportBatchCopyImportRow,
        from duplicateStatuses: [ImportBatchCopyImportRow.ID: String]
    ) -> ImportBatchCopyImportRow {
        guard let existingPath = duplicateStatuses[row.id] else { return row }
        var restoredRow = row
        restoredRow.status = .duplicate(existingPath: existingPath, strategy: .skip)
        return restoredRow
    }

    private func restoreDuplicateStrategy(
        for row: ImportBatchCopyImportRow,
        from strategies: [ImportBatchCopyImportRow.ID: ImportBatchDuplicateResolutionStrategy]
    ) -> ImportBatchCopyImportRow {
        guard let strategy = strategies[row.id] else { return row }
        guard case .duplicate(let existingPath, _) = row.status else { return row }
        var restoredRow = row
        restoredRow.status = .duplicate(existingPath: existingPath, strategy: strategy)
        return restoredRow
    }

    private func duplicateStrategy(for row: ImportBatchCopyImportRow) -> DuplicateStrategy {
        row.duplicateResolution?.duplicateStrategy ?? .ask
    }

    private func handleDuplicateFile(_ error: Error, at rowIndex: Int) -> Bool {
        guard let coreError = error as? CoreError else { return false }
        guard case .DuplicateFile(let existingPath) = coreError else { return false }
        rows[rowIndex].status = .duplicate(existingPath: existingPath, strategy: .skip)
        return true
    }

    private func markSkippedDuplicates() {
        for index in rows.indices where rows[index].duplicateResolution == .skip {
            if case .duplicate(let existingPath, _) = rows[index].status {
                rows[index].status = .skippedDuplicate(existingPath: existingPath)
            }
        }
    }
}

private struct ImportBatchCopyCycleResult {
    var entry: FileEntrySnapshot?
    var completed: Int
    var failed: Int
    var total: Int
    var currentPath: String
    var lastImportedPath: String?
    var stoppedForDuplicate: Bool

    var progress: ImportBatchProgressSnapshot {
        ImportBatchProgressSnapshot(
            completed: completed,
            failed: failed,
            total: total,
            remaining: total - completed - failed,
            currentPath: currentPath
        )
    }

    static func success(
        entry: FileEntrySnapshot,
        completed: Int,
        failed: Int,
        total: Int,
        currentPath: String
    ) -> ImportBatchCopyCycleResult {
        ImportBatchCopyCycleResult(
            entry: entry,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            lastImportedPath: entry.path,
            stoppedForDuplicate: false
        )
    }

    static func failure(
        completed: Int,
        failed: Int,
        total: Int,
        currentPath: String
    ) -> ImportBatchCopyCycleResult {
        ImportBatchCopyCycleResult(
            entry: nil,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            lastImportedPath: nil,
            stoppedForDuplicate: false
        )
    }

    static func duplicate(
        completed: Int,
        failed: Int,
        total: Int,
        currentPath: String
    ) -> ImportBatchCopyCycleResult {
        ImportBatchCopyCycleResult(
            entry: nil,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            lastImportedPath: nil,
            stoppedForDuplicate: true
        )
    }
}
