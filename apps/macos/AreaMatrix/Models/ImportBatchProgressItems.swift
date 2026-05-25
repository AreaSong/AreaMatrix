import Foundation

enum ImportConflictBatchConflictTypeSnapshot: String, Equatable, Hashable {
    case duplicateHash = "DuplicateHash"
    case sameNameDifferentContent = "SameNameDifferentContent"

    var title: String {
        switch self {
        case .duplicateHash: "Duplicate content"
        case .sameNameDifferentContent: "Same name, different content"
        }
    }
}

enum ImportConflictBatchStrategySnapshot: String, Equatable, Hashable {
    case skip = "Skip"
    case keepBoth = "KeepBoth"
    case replace = "Replace"
    case askPerItem = "AskPerItem"

    var title: String {
        switch self {
        case .skip: "Skip"
        case .keepBoth: "Keep both"
        case .replace: "Replace"
        case .askPerItem: "Ask per item"
        }
    }
}

enum ImportConflictBatchPreviewStatusSnapshot: String, Equatable, Hashable {
    case ready = "Ready"
    case pending = "Pending"
    case needsConfirmation = "Needs confirmation"
    case blocked = "Blocked"
    case failed = "Failed"
}

enum ImportConflictBatchResultStatusSnapshot: String, Equatable, Hashable {
    case skipped = "Skipped"
    case keptBoth = "Kept both"
    case replaced = "Replaced"
    case queuedForPerItem = "Queued for per item"
    case pending = "Pending"
    case failed = "Failed"
}

struct ImportConflictBatchPreviewRequestSnapshot: Equatable {
    var importSessionID: String
    var conflictIDs: [String]
    var duplicateStrategy: ImportConflictBatchStrategySnapshot
    var sameNameStrategy: ImportConflictBatchStrategySnapshot
    var applyToAllSimilarConflicts: Bool
}

struct ImportConflictBatchApplyRequestSnapshot: Equatable {
    var importSessionID: String
    var conflictIDs: [String]
    var duplicateStrategy: ImportConflictBatchStrategySnapshot
    var sameNameStrategy: ImportConflictBatchStrategySnapshot
    var applyToAllSimilarConflicts: Bool
    var replaceConfirmed: Bool
}

struct ImportConflictBatchPreviewItemSnapshot: Equatable, Identifiable {
    var conflictID: String
    var conflictType: ImportConflictBatchConflictTypeSnapshot
    var existingFileID: Int64?
    var existingPath: String?
    var incomingPath: String
    var targetPath: String?
    var selectedStrategy: ImportConflictBatchStrategySnapshot
    var status: ImportConflictBatchPreviewStatusSnapshot
    var willReplace: Bool
    var willKeepBoth: Bool
    var willSkip: Bool
    var willAskPerItem: Bool
    var indexOnly: Bool
    var riskSummary: String
    var reason: String?

    var id: String { conflictID }

    static func pendingPlaceholder(conflictID: String) -> ImportConflictBatchPreviewItemSnapshot {
        ImportConflictBatchPreviewItemSnapshot(
            conflictID: conflictID,
            conflictType: .duplicateHash,
            existingFileID: nil,
            existingPath: nil,
            incomingPath: conflictID,
            targetPath: nil,
            selectedStrategy: .skip,
            status: .pending,
            willReplace: false,
            willKeepBoth: false,
            willSkip: false,
            willAskPerItem: false,
            indexOnly: false,
            riskSummary: "Waiting for Core preview.",
            reason: nil
        )
    }
}

struct ImportConflictBatchPreviewReportSnapshot: Equatable {
    var importSessionID: String
    var previewToken: String
    var applyToAllSimilarConflicts: Bool
    var requestedConflictCount: Int64
    var duplicateConflictCount: Int64
    var sameNameConflictCount: Int64
    var includedCount: Int64
    var pendingCount: Int64
    var blockedCount: Int64
    var replaceCount: Int64
    var skipCount: Int64
    var keepBothCount: Int64
    var askPerItemCount: Int64
    var trashAvailable: Bool
    var undoAvailable: Bool
    var canApply: Bool
    var applyBlockedReason: String?
    var replaceConfirmationRequired: Bool
    var replaceConfirmationSummary: String?
    var items: [ImportConflictBatchPreviewItemSnapshot]
}

struct ImportConflictBatchItemResultSnapshot: Equatable, Identifiable {
    var conflictID: String
    var conflictType: ImportConflictBatchConflictTypeSnapshot
    var appliedStrategy: ImportConflictBatchStrategySnapshot
    var status: ImportConflictBatchResultStatusSnapshot
    var fileID: Int64?
    var finalPath: String?
    var error: String?

    var id: String { conflictID }
}

struct ImportConflictBatchApplyReportSnapshot: Equatable {
    var importSessionID: String
    var requestedConflictCount: Int64
    var resolvedCount: Int64
    var skippedCount: Int64
    var keptBothCount: Int64
    var replacedCount: Int64
    var queuedForPerItemCount: Int64
    var pendingCount: Int64
    var failedCount: Int64
    var itemResults: [ImportConflictBatchItemResultSnapshot]
    var affectedFileIDs: [Int64]
    var undoToken: String?
    var changeLogActions: [String]
    var failureSummary: String?
}

struct ImportConflictBatchApplyResult: Equatable {
    var report: ImportConflictBatchApplyReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

enum ImportConflictBatchPreviewState: Equatable {
    case idle
    case loading(previous: ImportConflictBatchPreviewReportSnapshot?)
    case loaded(ImportConflictBatchPreviewReportSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: ImportConflictBatchPreviewReportSnapshot?)

    var report: ImportConflictBatchPreviewReportSnapshot? {
        switch self {
        case let .loaded(report), let .loading(report?), let .failed(_, report?):
            report
        case .idle, .loading, .failed:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping, _) = self else { return nil }
        return mapping
    }
}

struct ImportConflictBatchRoute: Equatable {
    var importSessionID: String
    var conflictIDs: [String]
    var source: CommandPaletteLinkedPageRoute?
}

struct ImportConflictBatchProgressMetadata: Codable, Equatable {
    var importSessionID: String
    var conflictID: String
}

extension ImportConflictBatchProgressMetadata {
    init?(importSessionID: String?, conflictID: String?) {
        let session = importSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let conflict = conflictID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !session.isEmpty, !conflict.isEmpty else { return nil }
        self.importSessionID = session
        self.conflictID = conflict
    }
}

extension ImportConflictBatchRoute {
    init?(metadata: [ImportConflictBatchProgressMetadata], source: CommandPaletteLinkedPageRoute?) {
        guard let importSessionID = metadata.first?.importSessionID else { return nil }
        var conflictIDs: [String] = []
        for item in metadata where item.importSessionID == importSessionID && !conflictIDs.contains(item.conflictID) {
            conflictIDs.append(item.conflictID)
        }
        guard !conflictIDs.isEmpty else { return nil }
        self.importSessionID = importSessionID
        self.conflictIDs = conflictIDs
        self.source = source
    }
}

@MainActor
extension ImportBatchCopyImportModel {
    func progressItems() -> [ImportBatchProgressSnapshot.Item] {
        rows.map { row in
            ImportBatchProgressSnapshot.Item(
                sourcePath: row.sourcePath,
                targetPath: targetRelativePath(for: row, destination: selectedDestination),
                phase: Self.progressPhase(for: row.status),
                errorMessage: Self.progressErrorMessage(for: row.status),
                existingRelativePath: row.existingConflictPath,
                importConflictBatch: importConflictBatchMetadata(for: row)
            )
        }
    }

    private func importConflictBatchMetadata(
        for row: ImportBatchCopyImportRow
    ) -> ImportConflictBatchProgressMetadata? {
        guard let importSessionID = normalizedImportConflictBatchSessionID,
              let conflictID = request?.importConflictID(forSourcePath: row.sourcePath) else { return nil }
        return ImportConflictBatchProgressMetadata(
            importSessionID: importSessionID,
            conflictID: conflictID
        )
    }

    private static func progressPhase(
        for status: ImportBatchCopyImportRowStatus
    ) -> ImportBatchProgressSnapshot.Phase {
        switch status {
        case let .importing(mode):
            mode.importProgressPhase
        case .imported:
            .done
        case .error:
            .failed
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked,
             .skippedDuplicate, .skippedICloud:
            .pending
        }
    }

    private static func progressErrorMessage(for status: ImportBatchCopyImportRowStatus) -> String? {
        guard case let .error(message) = status else { return nil }
        return message
    }
}

private extension ImportSingleFileStorageMode {
    var importProgressPhase: ImportBatchProgressSnapshot.Phase {
        switch self {
        case .copy:
            .copying
        case .move:
            .moving
        case .indexOnly:
            .writingIndex
        }
    }
}
