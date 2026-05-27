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

// swiftlint:disable:next type_name
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

    var id: String {
        conflictID
    }

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

    var id: String {
        conflictID
    }
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

struct ImportConflictBatchPerItemRoute: Equatable, Identifiable {
    var conflictID: String
    var conflictType: ImportConflictBatchConflictTypeSnapshot
    var page: ImportSingleFileConflictPage
    var existingPath: String?
    var incomingPath: String
    var targetPath: String?

    var id: String {
        conflictID
    }

    var routeLabel: String {
        page.routeLabel
    }

    var replaceConfirmationRouteLabel: String {
        "S1-24 replace-confirm"
    }
}

struct ImportConflictBatchPerItemQueue: Equatable {
    var importSessionID: String
    var routes: [ImportConflictBatchPerItemRoute]

    var summary: String {
        "Queued \(routes.count) conflicts for per-item review."
    }

    static func make(from preview: ImportConflictBatchPreviewReportSnapshot) -> ImportConflictBatchPerItemQueue? {
        let routes = preview.items.compactMap(ImportConflictBatchPerItemRoute.init)
        guard !routes.isEmpty else { return nil }
        return ImportConflictBatchPerItemQueue(importSessionID: preview.importSessionID, routes: routes)
    }
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

extension ImportConflictBatchPerItemRoute {
    init?(_ item: ImportConflictBatchPreviewItemSnapshot) {
        guard item.status == .ready || item.status == .needsConfirmation else { return nil }
        guard item.willAskPerItem || item.selectedStrategy == .askPerItem else { return nil }
        switch item.conflictType {
        case .duplicateHash:
            page = .duplicate
        case .sameNameDifferentContent:
            page = .name
        }
        conflictID = item.conflictID
        conflictType = item.conflictType
        existingPath = item.existingPath
        incomingPath = item.incomingPath
        targetPath = item.targetPath
    }
}

extension ImportConflictBatchPreviewReportSnapshot {
    static func emptyManualScope(
        importSessionID: String,
        sourceItems: [ImportConflictBatchPreviewItemSnapshot],
        fallbackConflictIDs: [String]
    ) -> ImportConflictBatchPreviewReportSnapshot {
        let items = sourceItems.isEmpty
            ? fallbackConflictIDs.map(ImportConflictBatchPreviewItemSnapshot.pendingPlaceholder)
            : sourceItems
        return ImportConflictBatchPreviewReportSnapshot(
            importSessionID: importSessionID,
            previewToken: "",
            applyToAllSimilarConflicts: false,
            requestedConflictCount: 0,
            duplicateConflictCount: Int64(items.filter { $0.conflictType == .duplicateHash }.count),
            sameNameConflictCount: Int64(items.filter { $0.conflictType == .sameNameDifferentContent }.count),
            includedCount: 0,
            pendingCount: Int64(items.count),
            blockedCount: 0,
            replaceCount: 0,
            skipCount: 0,
            keepBothCount: 0,
            askPerItemCount: 0,
            trashAvailable: false,
            undoAvailable: false,
            canApply: false,
            applyBlockedReason: "Select at least one conflict.",
            replaceConfirmationRequired: false,
            replaceConfirmationSummary: nil,
            items: items.map(\.notSelected)
        )
    }
}

extension ImportConflictBatchPreviewItemSnapshot {
    var isActionablePreviewItem: Bool {
        status == .ready || status == .needsConfirmation
    }

    var isPerItemQueueItem: Bool {
        isActionablePreviewItem && (willAskPerItem || selectedStrategy == .askPerItem)
    }

    var notSelected: ImportConflictBatchPreviewItemSnapshot {
        var copy = self
        copy.status = .pending
        copy.willReplace = false
        copy.willKeepBoth = false
        copy.willSkip = false
        copy.willAskPerItem = false
        copy.reason = "Not selected"
        return copy
    }
}

@MainActor
extension ImportBatchCopyImportModel {
    var conflictBatchPerItemSummary: String? {
        conflictBatchPerItemQueue?.summary
    }

    var conflictBatchPerItemRouteLabels: [String] {
        conflictBatchPerItemQueue?.routes.map(\.routeLabel) ?? []
    }

    var conflictBatchScopeSummary: String {
        if hasEmptyManualConflictBatchScope { return "Select at least one conflict." }
        guard let preview = conflictBatchPreviewReport else { return "Checking conflicts..." }
        if preview.applyToAllSimilarConflicts {
            return "Will apply to \(preview.duplicateConflictCount) duplicate conflicts and " +
                "\(preview.sameNameConflictCount) same-name conflicts."
        }
        return "Will apply to \(preview.includedCount) selected conflicts."
    }

    var conflictBatchApplyDisabledReason: String? {
        if isConflictBatchApplying { return "Applying..." }
        if hasEmptyManualConflictBatchScope { return "Select at least one conflict." }
        guard let preview = conflictBatchPreviewReport else { return "Checking conflicts..." }
        if !preview.canApply {
            return preview.applyBlockedReason ?? "Could not prepare conflict strategy."
        }
        if ImportConflictBatchValidation.actionableIncludedCount(preview: preview) == 0 {
            return "All conflicts in this scope are blocked."
        }
        let replaceConfirmed = isConflictBatchReplaceConfirmed || preview.replaceConfirmationRequired
        guard let request = makeImportConflictBatchApplyRequest(replaceConfirmed: replaceConfirmed),
              ImportConflictBatchValidation.canApply(preview: preview, request: request, isApplying: false) else {
            return "Refresh conflict strategy preview."
        }
        return nil
    }

    var conflictBatchAskPerItemDisabledReason: String? {
        if isConflictBatchApplying { return "Applying..." }
        if hasEmptyManualConflictBatchScope { return "Select at least one conflict." }
        guard let preview = conflictBatchPreviewReport else { return "Checking conflicts..." }
        if ImportConflictBatchValidation.canAskPerItem(preview: preview, isApplying: false) { return nil }
        if preview.includedCount > 0 {
            return "All conflicts in this scope are blocked."
        }
        return preview.applyBlockedReason ?? "Select at least one conflict."
    }

    var hasEmptyManualConflictBatchScope: Bool {
        showsCoreConflictBatchReview
            && !appliesConflictBatchToAll
            && selectedConflictBatchIDs.isEmpty
    }

    func emptyManualConflictBatchPreview() -> ImportConflictBatchPreviewReportSnapshot? {
        guard let importSessionID = normalizedImportConflictBatchSessionID else { return nil }
        return .emptyManualScope(
            importSessionID: importSessionID,
            sourceItems: conflictBatchPreviewState.report?.items ?? [],
            fallbackConflictIDs: request?.importConflictIDs ?? []
        )
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
