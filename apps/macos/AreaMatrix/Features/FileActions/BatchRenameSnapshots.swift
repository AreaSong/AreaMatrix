import Foundation

enum BatchRenameModeSnapshot: String, CaseIterable, Equatable, Identifiable {
    case prefix = "Prefix"
    case datePrefix = "Date prefix"
    case keepBaseSequence = "Keep base + sequence"
    case replaceText = "Replace text"

    var id: String {
        rawValue
    }

    var displayName: String {
        L10n.string(rawValue)
    }
}

enum BatchRenameDateSourceSnapshot: String, CaseIterable, Equatable, Identifiable {
    case imported = "Imported"
    case modified = "Modified"
    case today = "Today"

    var id: String {
        rawValue
    }

    var displayName: String {
        L10n.string(rawValue)
    }
}

struct BatchRenameRuleSnapshot: Equatable {
    var mode: BatchRenameModeSnapshot
    var prefix: String?
    var dateSource: BatchRenameDateSourceSnapshot?
    var dateFormat: String?
    var separator: String?
    var startNumber: Int64?
    var padding: Int64?
    var find: String?
    var replacement: String?
    var caseSensitive: Bool
}

enum BatchRenamePreviewStatusSnapshot: String, Equatable {
    case ok = "OK"
    case error = "ERROR"
    case nameConflict = "NAME"
    case missing = "MISSING"
    case readOnly = "READONLY"
    case displayOnly = "DISPLAY_ONLY"
    case unchanged = "UNCHANGED"
    case externalChange = "EXTERNAL_CHANGE"

    var displayName: String {
        switch self {
        case .ok: L10n.string("Ready")
        case .error: L10n.string("Error")
        case .nameConflict: L10n.string("Name conflict")
        case .missing: L10n.string("Missing")
        case .readOnly: L10n.string("Read-only")
        case .displayOnly: L10n.string("Display only")
        case .unchanged: L10n.string("Unchanged")
        case .externalChange: L10n.string("External change")
        }
    }
}

struct BatchRenamePreviewItemSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var currentPath: String?
    var originalName: String?
    var newName: String?
    var targetPath: String?
    var status: BatchRenamePreviewStatusSnapshot
    var reason: String?

    var id: Int64 {
        fileID
    }
}

struct BatchRenamePreviewReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var rule: BatchRenameRuleSnapshot
    var previewToken: String
    var willRenameCount: Int64
    var displayOnlyCount: Int64
    var unchangedCount: Int64
    var blockedCount: Int64
    var conflictCount: Int64
    var items: [BatchRenamePreviewItemSnapshot]
    var canApply: Bool
    var applyBlockedReason: String?
}

enum BatchRenameResultStatusSnapshot: String, Equatable {
    case renamed = "Renamed"
    case displayNameUpdated = "Display name updated"
    case unchanged = "Unchanged"
    case skipped = "Skipped"
    case failed = "Failed"

    var displayName: String {
        L10n.string(rawValue)
    }
}

struct BatchRenameItemResultSnapshot: Equatable, Identifiable {
    var fileID: Int64
    var originalName: String?
    var finalName: String?
    var finalPath: String?
    var status: BatchRenameResultStatusSnapshot
    var error: String?

    var id: Int64 {
        fileID
    }
}

struct BatchRenameReportSnapshot: Equatable {
    var requestedFileCount: Int64
    var renamedCount: Int64
    var displayNameUpdatedCount: Int64
    var unchangedCount: Int64
    var skippedCount: Int64
    var failedCount: Int64
    var itemResults: [BatchRenameItemResultSnapshot]
    var updatedFiles: [FileEntrySnapshot]
    var undoToken: String?
}

extension BatchRenameRuleSnapshot {
    init(coreRule: BatchRenameRule) {
        mode = BatchRenameModeSnapshot(coreRule.mode)
        prefix = coreRule.prefix
        dateSource = coreRule.dateSource.map(BatchRenameDateSourceSnapshot.init)
        dateFormat = coreRule.dateFormat
        separator = coreRule.separator
        startNumber = coreRule.startNumber
        padding = coreRule.padding
        find = coreRule.find
        replacement = coreRule.replacement
        caseSensitive = coreRule.caseSensitive
    }
}

extension BatchRenamePreviewItemSnapshot {
    init(_ coreItem: BatchRenamePreviewItem) {
        fileID = coreItem.fileId
        currentPath = coreItem.currentPath
        originalName = coreItem.originalName
        newName = coreItem.newName
        targetPath = coreItem.targetPath
        status = BatchRenamePreviewStatusSnapshot(coreItem.status)
        reason = coreItem.reason
    }
}

extension BatchRenameItemResultSnapshot {
    init(_ coreResult: BatchRenameItemResult) {
        fileID = coreResult.fileId
        originalName = coreResult.originalName
        finalName = coreResult.finalName
        finalPath = coreResult.finalPath
        status = BatchRenameResultStatusSnapshot(coreResult.status)
        error = coreResult.error
    }
}

private extension BatchRenameModeSnapshot {
    init(_ core: BatchRenameMode) {
        switch core {
        case .prefix: self = .prefix
        case .datePrefix: self = .datePrefix
        case .keepBaseSequence: self = .keepBaseSequence
        case .replaceText: self = .replaceText
        }
    }
}

private extension BatchRenameDateSourceSnapshot {
    init(_ core: BatchRenameDateSource) {
        switch core {
        case .imported: self = .imported
        case .modified: self = .modified
        case .today: self = .today
        }
    }
}

private extension BatchRenamePreviewStatusSnapshot {
    init(_ coreStatus: BatchRenamePreviewStatus) {
        switch coreStatus {
        case .ok: self = .ok
        case .error: self = .error
        case .nameConflict: self = .nameConflict
        case .missing: self = .missing
        case .readOnly: self = .readOnly
        case .displayOnly: self = .displayOnly
        case .unchanged: self = .unchanged
        case .externalChange: self = .externalChange
        }
    }
}

private extension BatchRenameResultStatusSnapshot {
    init(_ coreStatus: BatchRenameResultStatus) {
        switch coreStatus {
        case .renamed: self = .renamed
        case .displayNameUpdated: self = .displayNameUpdated
        case .unchanged: self = .unchanged
        case .skipped: self = .skipped
        case .failed: self = .failed
        }
    }
}
