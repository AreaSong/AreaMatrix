import Foundation

enum ImportBatchCopyImportRowStatus: Equatable, Sendable {
    case loading
    case ready(reasonLabel: String)
    case duplicate(existingPath: String, strategy: ImportBatchDuplicateResolutionStrategy)
    case importing
    case skippedDuplicate(existingPath: String)
    case imported
    case error(String)

    var tag: String {
        switch self {
        case .loading:
            return "PREVIEW"
        case .ready:
            return "OK"
        case .duplicate:
            return "DUP"
        case .importing:
            return "IMPORTING"
        case .skippedDuplicate:
            return "SKIPPED"
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
        case .duplicate(let existingPath, let strategy):
            return "\(strategy.title): \(existingPath)"
        case .importing:
            return "正在复制导入..."
        case .skippedDuplicate(let existingPath):
            return "Duplicate skipped: \(existingPath)"
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

enum ImportBatchDuplicateResolutionStrategy: String, CaseIterable, Equatable, Sendable {
    case skip
    case keepBoth

    var title: String {
        switch self {
        case .skip:
            return "Skip"
        case .keepBoth:
            return "Keep both"
        }
    }

    var duplicateStrategy: DuplicateStrategy {
        switch self {
        case .skip:
            return .skip
        case .keepBoth:
            return .keepBoth
        }
    }

    var importsIncomingFile: Bool {
        self == .keepBoth
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

    var duplicateResolution: ImportBatchDuplicateResolutionStrategy? {
        if case .duplicate(_, let strategy) = status {
            return strategy
        }
        if case .skippedDuplicate = status {
            return .skip
        }
        return nil
    }

    var isDuplicateConflictRow: Bool {
        switch status {
        case .duplicate, .skippedDuplicate:
            return true
        case .loading, .ready, .importing, .imported, .error:
            return false
        }
    }

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
    var pendingDuplicateCount: Int
}
