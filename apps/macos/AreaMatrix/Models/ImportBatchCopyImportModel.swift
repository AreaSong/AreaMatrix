import Foundation

enum ImportBatchCopyImportRowStatus: Equatable, Sendable {
    case loading
    case ready(reasonLabel: String)
    case importing
    case imported
    case error(String)

    var tag: String {
        switch self {
        case .loading:
            return "PREVIEW"
        case .ready:
            return "OK"
        case .importing:
            return "IMPORTING"
        case .imported:
            return "IMPORTED"
        case .error:
            return "ERROR"
        }
    }

    var detail: String? {
        switch self {
        case .loading:
            return "Preparing preview..."
        case .ready(let reasonLabel), .error(let reasonLabel):
            return reasonLabel
        case .importing:
            return "正在复制导入..."
        case .imported:
            return "已复制导入"
        }
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

struct ImportBatchCopyImportRow: Identifiable, Equatable, Sendable {
    var originalName: String
    var sourcePath: String
    var sourceURL: URL
    var sizeBytes: Int64?
    var predictedCategory: String?
    var suggestedName: String
    var status: ImportBatchCopyImportRowStatus

    var id: String { sourcePath }

    func displayCategory(for destination: ImportBatchDestinationOption) -> String {
        switch destination {
        case .autoClassify:
            return predictedCategory ?? "未生成"
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return "repo root"
        }
    }
}

enum ImportBatchCopyImportStatus: Equatable, Sendable {
    case idle
    case importing(completed: Int, total: Int, failed: Int, currentPath: String)
    case imported(successful: Int, failed: Int)

    var isImporting: Bool {
        if case .importing = self {
            return true
        }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .importing(let completed, let total, let failed, _):
            return "正在复制导入：已完成 \(completed)/\(total)，失败 \(failed)"
        case .imported(let successful, let failed):
            return "批量导入完成：成功 \(successful)，失败 \(failed)"
        }
    }
}

struct ImportBatchProgressSnapshot: Equatable, Sendable {
    var completed: Int
    var failed: Int
    var total: Int
    var remaining: Int
    var currentPath: String
}

struct ImportBatchImportResult: Equatable, Sendable {
    var succeededEntries: [FileEntrySnapshot]
    var failedCount: Int
    var total: Int
    var lastImportedPath: String
}

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
        if importableRows.isEmpty {
            return "没有可导入的批量项目"
        }
        return nil
    }

    var importableRows: [ImportBatchCopyImportRow] {
        rows.filter { $0.status.isReady }
    }

    func applyPreviewRows(
        _ previewRows: [ImportBatchPreviewRow],
        request: ImportEntryRequest?,
        selectedDestination: ImportBatchDestinationOption
    ) {
        self.rows = mapPreviewRows(previewRows, request: request)
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
            if let entry = cycle.entry {
                succeededEntries.append(entry)
            }
            reportProgress(cycle.progress)
        }

        status = .imported(successful: completed, failed: failed)
        return ImportBatchImportResult(
            succeededEntries: succeededEntries,
            failedCount: failed,
            total: total,
            lastImportedPath: lastImportedPath
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
            duplicateStrategy: .ask
        )
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
        case .error(let message):
            return .error(message)
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
            lastImportedPath: entry.path
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
            lastImportedPath: nil
        )
    }
}
