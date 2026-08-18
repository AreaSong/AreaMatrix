public enum BatchRenameModeSnapshot: String, CaseIterable, Equatable, Identifiable, Sendable {
    case prefix = "Prefix"
    case datePrefix = "Date prefix"
    case keepBaseSequence = "Keep base + sequence"
    case replaceText = "Replace text"

    public var id: String {
        rawValue
    }
}

public enum BatchRenameDateSourceSnapshot: String, CaseIterable, Equatable, Identifiable, Sendable {
    case imported = "Imported"
    case modified = "Modified"
    case today = "Today"

    public var id: String {
        rawValue
    }
}

public struct BatchRenameRuleSnapshot: Equatable, Sendable {
    public var mode: BatchRenameModeSnapshot
    public var prefix: String?
    public var dateSource: BatchRenameDateSourceSnapshot?
    public var dateFormat: String?
    public var separator: String?
    public var startNumber: Int64?
    public var padding: Int64?
    public var find: String?
    public var replacement: String?
    public var caseSensitive: Bool

    public init(
        mode: BatchRenameModeSnapshot,
        prefix: String?,
        dateSource: BatchRenameDateSourceSnapshot?,
        dateFormat: String?,
        separator: String?,
        startNumber: Int64?,
        padding: Int64?,
        find: String?,
        replacement: String?,
        caseSensitive: Bool
    ) {
        self.mode = mode
        self.prefix = prefix
        self.dateSource = dateSource
        self.dateFormat = dateFormat
        self.separator = separator
        self.startNumber = startNumber
        self.padding = padding
        self.find = find
        self.replacement = replacement
        self.caseSensitive = caseSensitive
    }
}

public enum BatchRenamePreviewStatusSnapshot: String, Equatable, Sendable {
    case ok = "OK"
    case error = "ERROR"
    case nameConflict = "NAME"
    case missing = "MISSING"
    case readOnly = "READONLY"
    case displayOnly = "DISPLAY_ONLY"
    case unchanged = "UNCHANGED"
    case externalChange = "EXTERNAL_CHANGE"
}

public struct BatchRenamePreviewItemSnapshot: Equatable, Identifiable, Sendable {
    public var fileID: Int64
    public var currentPath: String?
    public var originalName: String?
    public var newName: String?
    public var targetPath: String?
    public var status: BatchRenamePreviewStatusSnapshot
    public var reason: String?

    public var id: Int64 {
        fileID
    }

    public init(
        fileID: Int64,
        currentPath: String?,
        originalName: String?,
        newName: String?,
        targetPath: String?,
        status: BatchRenamePreviewStatusSnapshot,
        reason: String?
    ) {
        self.fileID = fileID
        self.currentPath = currentPath
        self.originalName = originalName
        self.newName = newName
        self.targetPath = targetPath
        self.status = status
        self.reason = reason
    }
}

public struct BatchRenamePreviewReportSnapshot: Equatable, Sendable {
    public var requestedFileCount: Int64
    public var rule: BatchRenameRuleSnapshot
    public var previewToken: String
    public var willRenameCount: Int64
    public var displayOnlyCount: Int64
    public var unchangedCount: Int64
    public var blockedCount: Int64
    public var conflictCount: Int64
    public var items: [BatchRenamePreviewItemSnapshot]
    public var canApply: Bool
    public var applyBlockedReason: String?

    public init(
        requestedFileCount: Int64,
        rule: BatchRenameRuleSnapshot,
        previewToken: String,
        willRenameCount: Int64,
        displayOnlyCount: Int64,
        unchangedCount: Int64,
        blockedCount: Int64,
        conflictCount: Int64,
        items: [BatchRenamePreviewItemSnapshot],
        canApply: Bool,
        applyBlockedReason: String?
    ) {
        self.requestedFileCount = requestedFileCount
        self.rule = rule
        self.previewToken = previewToken
        self.willRenameCount = willRenameCount
        self.displayOnlyCount = displayOnlyCount
        self.unchangedCount = unchangedCount
        self.blockedCount = blockedCount
        self.conflictCount = conflictCount
        self.items = items
        self.canApply = canApply
        self.applyBlockedReason = applyBlockedReason
    }
}

public enum BatchRenameResultStatusSnapshot: String, Equatable, Sendable {
    case renamed = "Renamed"
    case displayNameUpdated = "Display name updated"
    case unchanged = "Unchanged"
    case skipped = "Skipped"
    case failed = "Failed"
}

public struct BatchRenameItemResultSnapshot: Equatable, Identifiable, Sendable {
    public var fileID: Int64
    public var originalName: String?
    public var finalName: String?
    public var finalPath: String?
    public var status: BatchRenameResultStatusSnapshot
    public var error: String?

    public var id: Int64 {
        fileID
    }

    public init(
        fileID: Int64,
        originalName: String?,
        finalName: String?,
        finalPath: String?,
        status: BatchRenameResultStatusSnapshot,
        error: String?
    ) {
        self.fileID = fileID
        self.originalName = originalName
        self.finalName = finalName
        self.finalPath = finalPath
        self.status = status
        self.error = error
    }
}
