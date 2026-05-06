import Foundation

enum ImportBatchCopyImportRowStatus: Equatable, Sendable {
    case loading
    case ready(reasonLabel: String)
    case duplicate(
        existingPath: String,
        strategy: ImportBatchDuplicateResolutionStrategy,
        isReplaceConfirmed: Bool
    )
    case nameConflict(existingPath: String, resolution: ImportBatchNameConflictResolution)
    case iCloudPlaceholder(path: String, message: String)
    case blocked(String)
    case importing
    case skippedDuplicate(existingPath: String)
    case skippedICloud(path: String)
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
        case .nameConflict:
            return "NAME"
        case .iCloudPlaceholder:
            return "ICLOUD"
        case .blocked:
            return "BLOCKED"
        case .importing:
            return "IMPORTING"
        case .skippedDuplicate:
            return "SKIPPED"
        case .skippedICloud:
            return "PENDING"
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
        case .duplicate(let existingPath, let strategy, let isReplaceConfirmed):
            if strategy == .replace, isReplaceConfirmed {
                return "Replace confirmed: \(existingPath)"
            }
            return "\(strategy.title): \(existingPath)"
        case .nameConflict(let existingPath, let resolution):
            return "\(resolution.title): \(existingPath)"
        case .iCloudPlaceholder(_, let message):
            return message
        case .blocked(let message):
            return message
        case .importing:
            return "正在复制导入..."
        case .skippedDuplicate(let existingPath):
            return "Duplicate skipped: \(existingPath)"
        case .skippedICloud(let path):
            return "iCloud pending: \(path)"
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
    case replace

    var title: String {
        switch self {
        case .skip:
            return "Skip"
        case .keepBoth:
            return "Keep both"
        case .replace:
            return "Replace"
        }
    }

    var duplicateStrategy: DuplicateStrategy {
        switch self {
        case .skip:
            return .skip
        case .keepBoth:
            return .keepBoth
        case .replace:
            return .overwrite
        }
    }

    var importsIncomingFile: Bool {
        self == .keepBoth || self == .replace
    }
}

enum ImportBatchNameConflictResolution: Hashable, Sendable {
    case keepBoth
    case renameIncoming(String)
    case replace(isConfirmed: Bool)

    var title: String {
        switch self {
        case .keepBoth:
            return "Keep both (auto-number)"
        case .renameIncoming:
            return "Rename incoming"
        case .replace(let isConfirmed):
            return isConfirmed ? "Replace confirmed" : "Replace"
        }
    }

    var importsIncomingFile: Bool {
        switch self {
        case .keepBoth, .renameIncoming:
            return true
        case .replace(let isConfirmed):
            return isConfirmed
        }
    }

    var isReplace: Bool {
        if case .replace = self { return true }
        return false
    }
}

struct ImportBatchCopyImportRow: Identifiable, Equatable, Sendable {
    var originalName: String
    var sourcePath: String
    var sourceURL: URL
    var sizeBytes: Int64?
    var predictedCategory: String?
    var categoryOverride: String?
    var suggestedName: String
    var status: ImportBatchCopyImportRowStatus

    var id: String { sourcePath }

    var duplicateResolution: ImportBatchDuplicateResolutionStrategy? {
        if case .duplicate(_, let strategy, _) = status {
            return strategy
        }
        if case .skippedDuplicate = status {
            return .skip
        }
        return nil
    }

    var nameConflictResolution: ImportBatchNameConflictResolution? {
        if case .nameConflict(_, let resolution) = status {
            return resolution
        }
        return nil
    }

    var resolvedIncomingName: String {
        guard case .nameConflict(_, let resolution) = status else {
            return suggestedName
        }
        switch resolution {
        case .keepBoth, .replace:
            return suggestedName
        case .renameIncoming(let name):
            return name
        }
    }

    var isConflictReviewRow: Bool {
        switch status {
        case .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .skippedDuplicate, .skippedICloud:
            return true
        case .loading, .ready, .importing, .imported, .error:
            return false
        }
    }

    var isBlockedForImport: Bool {
        switch status {
        case .blocked:
            return true
        case .duplicate(_, .replace, false):
            return true
        case .nameConflict(_, .replace(false)):
            return true
        case .nameConflict(_, .renameIncoming(let name)):
            return ImportSingleFileFilenameValidator.validationMessage(for: name) != nil
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .importing,
             .skippedDuplicate, .skippedICloud, .imported, .error:
            return false
        }
    }

    var existingConflictPath: String? {
        switch status {
        case .duplicate(let existingPath, _, _), .nameConflict(let existingPath, _), .skippedDuplicate(let existingPath):
            return existingPath
        case .iCloudPlaceholder(let path, _), .skippedICloud(let path):
            return path
        case .loading, .ready, .blocked, .importing, .imported, .error:
            return nil
        }
    }

    var conflictLabel: String {
        switch status {
        case .duplicate, .skippedDuplicate:
            return "Duplicate content"
        case .nameConflict:
            return "Same name, different content"
        case .iCloudPlaceholder, .skippedICloud:
            return "iCloud placeholder"
        case .blocked:
            return "Blocked"
        case .loading, .ready, .importing, .imported, .error:
            return "-"
        }
    }

    func displayCategory(for destination: ImportBatchDestinationOption) -> String {
        if let categoryOverride {
            return categoryOverride
        }
        if destination == .repositoryRoot {
            return "repo root"
        }
        return resolvedCategory(for: destination) ?? "inbox"
    }

    func resolvedCategory(for destination: ImportBatchDestinationOption) -> String? {
        if let categoryOverride {
            return categoryOverride
        }
        return defaultCategory(for: destination)
    }

    func defaultCategory(for destination: ImportBatchDestinationOption) -> String? {
        switch destination {
        case .autoClassify:
            return predictedCategory ?? "inbox"
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return nil
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
    var skipped: Int = 0
    var pending: Int = 0
}

struct ImportBatchImportResult: Equatable, Sendable {
    var succeededEntries: [FileEntrySnapshot]
    var failedCount: Int
    var previewErrorCount: Int = 0
    var total: Int
    var lastImportedPath: String
    var pendingDuplicateCount: Int
    var skippedDuplicateCount: Int
    var pendingICloudCount: Int

    var needsResultSummary: Bool {
        failedCount > 0 || previewErrorCount > 0 || skippedDuplicateCount > 0 || pendingICloudCount > 0
    }

    func progressSnapshot(currentPath fallbackPath: String) -> ImportBatchProgressSnapshot {
        ImportBatchProgressSnapshot(
            completed: succeededEntries.count,
            failed: failedCount + previewErrorCount,
            total: total + previewErrorCount + skippedDuplicateCount + pendingICloudCount,
            remaining: 0,
            currentPath: lastImportedPath.isEmpty ? fallbackPath : lastImportedPath,
            skipped: skippedDuplicateCount,
            pending: pendingICloudCount
        )
    }
}
