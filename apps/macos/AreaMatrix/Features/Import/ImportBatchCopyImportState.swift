import Foundation

enum ImportBatchCopyImportRowStatus: Equatable {
    case loading
    case ready(reasonLabel: AppDisplayText)
    case duplicate(
        existingPath: String,
        strategy: ImportBatchDuplicateResolutionStrategy,
        isReplaceConfirmed: Bool
    )
    case nameConflict(existingPath: String, resolution: ImportBatchNameConflictResolution)
    case iCloudPlaceholder(path: String, message: AppDisplayText)
    case blocked(AppDisplayText)
    case importing(ImportSingleFileStorageMode)
    case skippedDuplicate(existingPath: String)
    case skippedICloud(path: String)
    case imported
    case error(AppDisplayText)

    var tag: String {
        switch self {
        case .loading:
            "PREVIEW"
        case .ready:
            "OK"
        case .duplicate:
            "DUP"
        case .nameConflict:
            "NAME"
        case .iCloudPlaceholder:
            "ICLOUD"
        case .blocked:
            "BLOCKED"
        case .importing:
            "IMPORTING"
        case .skippedDuplicate:
            "SKIPPED"
        case .skippedICloud:
            "PENDING"
        case .imported:
            "IMPORTED"
        case .error:
            "ERROR"
        }
    }

    var tagMessage: LocalizedMessage {
        ImportStatusTagLocalization.message(for: tag)
    }

    var detail: String? {
        switch self {
        case .loading:
            return L10n.string("Preparing preview...")
        case let .ready(reasonLabel), let .error(reasonLabel):
            return L10n.resolve(reasonLabel)
        case let .duplicate(existingPath, strategy, isReplaceConfirmed):
            if strategy == .replace, isReplaceConfirmed {
                return L10n.format("import.conflict.replace-confirmed", existingPath)
            }
            return L10n.format("import.conflict.strategy-path", strategy.title, existingPath)
        case let .nameConflict(existingPath, resolution):
            return L10n.format("import.conflict.resolution-path", resolution.title, existingPath)
        case let .iCloudPlaceholder(_, message):
            return L10n.resolve(message)
        case let .blocked(message):
            return L10n.resolve(message)
        case let .importing(mode):
            return mode.importingMessage
        case .skippedDuplicate, .skippedICloud, .imported:
            return completionDetail
        }
    }

    private var completionDetail: String {
        switch self {
        case let .skippedDuplicate(existingPath):
            L10n.format("import.preview.duplicate-skipped", existingPath)
        case let .skippedICloud(path):
            L10n.format("import.conflict.icloud-pending", path)
        case .imported:
            L10n.string("import.result.completed")
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .importing, .error:
            L10n.string("Import failed")
        }
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }
}

enum ImportStatusTagLocalization {
    static func message(for tag: String) -> LocalizedMessage {
        knownMessages[tag] ?? L10n.message("ERROR")
    }

    private static let knownMessages: [String: LocalizedMessage] = [
        "PREVIEW": L10n.message("PREVIEW"),
        "OK": L10n.message("OK"),
        "DUP": L10n.message("DUP"),
        "NAME": L10n.message("NAME"),
        "ICLOUD": L10n.message("ICLOUD"),
        "BLOCKED": L10n.message("BLOCKED"),
        "IMPORTING": L10n.message("IMPORTING"),
        "SKIPPED": L10n.message("SKIPPED"),
        "PENDING": L10n.message("PENDING"),
        "IMPORTED": L10n.message("IMPORTED"),
        "ERROR": L10n.message("ERROR")
    ]
}

enum ImportBatchDuplicateResolutionStrategy: String, CaseIterable, Equatable {
    case skip
    case keepBoth
    case replace

    var title: String {
        switch self {
        case .skip:
            L10n.string("Skip")
        case .keepBoth:
            L10n.string("Keep both")
        case .replace:
            L10n.string("Replace")
        }
    }

    var duplicateStrategy: DuplicateStrategy {
        switch self {
        case .skip:
            .skip
        case .keepBoth:
            .keepBoth
        case .replace:
            .overwrite
        }
    }

    var importsIncomingFile: Bool {
        self == .keepBoth || self == .replace
    }
}

enum ImportBatchNameConflictResolution: Hashable {
    case keepBoth
    case renameIncoming(String)
    case replace(isConfirmed: Bool)

    var title: String {
        switch self {
        case .keepBoth:
            L10n.string("Keep both (auto-number)")
        case .renameIncoming:
            L10n.string("Rename incoming")
        case let .replace(isConfirmed):
            if isConfirmed {
                L10n.string("Replace confirmed")
            } else {
                L10n.string("Replace")
            }
        }
    }

    var importsIncomingFile: Bool {
        switch self {
        case .keepBoth, .renameIncoming:
            true
        case let .replace(isConfirmed):
            isConfirmed
        }
    }

    var isReplace: Bool {
        if case .replace = self { return true }
        return false
    }
}

struct ImportBatchCopyImportRow: Identifiable, Equatable {
    var originalName: String
    var sourcePath: String
    var sourceURL: URL
    var sizeBytes: Int64?
    var predictedCategory: String?
    var categoryOverride: String?
    var suggestedName: String
    var status: ImportBatchCopyImportRowStatus

    var id: String {
        sourcePath
    }

    var duplicateResolution: ImportBatchDuplicateResolutionStrategy? {
        if case let .duplicate(_, strategy, _) = status {
            return strategy
        }
        if case .skippedDuplicate = status {
            return .skip
        }
        return nil
    }

    var nameConflictResolution: ImportBatchNameConflictResolution? {
        if case let .nameConflict(_, resolution) = status {
            return resolution
        }
        return nil
    }

    var resolvedIncomingName: String {
        guard case let .nameConflict(_, resolution) = status else {
            return suggestedName
        }
        switch resolution {
        case .keepBoth, .replace:
            return suggestedName
        case let .renameIncoming(name):
            return name
        }
    }

    var isConflictReviewRow: Bool {
        switch status {
        case .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .skippedDuplicate, .skippedICloud:
            true
        case .loading, .ready, .importing, .imported, .error:
            false
        }
    }

    var isBlockedForImport: Bool {
        switch status {
        case .blocked:
            true
        case .duplicate(_, .replace, false):
            true
        case .nameConflict(_, .replace(false)):
            true
        case let .nameConflict(_, .renameIncoming(name)):
            ImportSingleFileFilenameValidator.validationMessage(for: name) != nil
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .importing,
             .skippedDuplicate, .skippedICloud, .imported, .error:
            false
        }
    }

    var existingConflictPath: String? {
        switch status {
        case let .duplicate(existingPath, _, _), let .nameConflict(existingPath, _),
             let .skippedDuplicate(existingPath):
            existingPath
        case .loading, .ready, .iCloudPlaceholder, .blocked, .importing, .skippedICloud, .imported, .error:
            nil
        }
    }

    var conflictLabel: String {
        switch status {
        case .duplicate, .skippedDuplicate:
            L10n.string("Duplicate content")
        case .nameConflict:
            L10n.string("Same name, different content")
        case .iCloudPlaceholder, .skippedICloud:
            L10n.string("iCloud placeholder")
        case .blocked:
            L10n.string("Blocked")
        case .loading, .ready, .importing, .imported, .error:
            "-"
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
            predictedCategory ?? "inbox"
        case let .category(slug):
            slug
        case .repositoryRoot:
            nil
        }
    }
}

enum ImportBatchCopyImportStatus: Equatable {
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
            nil
        case let .importing(completed, total, failed, _):
            L10n.format("import.batch.importing", completed, total, failed)
        case let .imported(successful, failed):
            L10n.format("import.batch.completed", successful, failed)
        }
    }
}

extension ImportBatchCopyImportModel {
    var storageModeRiskMessage: String? {
        switch selectedStorageMode {
        case .copy:
            nil
        case .move:
            L10n.string("import.storage.moveRisk")
        case .indexOnly:
            L10n.string("import.storage.indexOnlyRisk")
        }
    }
}
