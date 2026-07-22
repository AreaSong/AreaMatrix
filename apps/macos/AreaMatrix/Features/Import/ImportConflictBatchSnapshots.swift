import Foundation

enum ImportConflictBatchConflictTypeSnapshot: String, Equatable, Hashable {
    case duplicateHash = "DuplicateHash"
    case sameNameDifferentContent = "SameNameDifferentContent"

    var title: String {
        switch self {
        case .duplicateHash: L10n.string("Duplicate content")
        case .sameNameDifferentContent: L10n.string("Same name, different content")
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
        case .skip: L10n.string("Skip")
        case .keepBoth: L10n.string("Keep both")
        case .replace: L10n.string("Replace")
        case .askPerItem: L10n.string("Ask per item")
        }
    }
}

enum ImportConflictBatchPreviewStatusSnapshot: String, Equatable, Hashable {
    case ready = "Ready"
    case pending = "Pending"
    case needsConfirmation = "Needs confirmation"
    case blocked = "Blocked"
    case failed = "Failed"

    var title: String {
        L10n.string(rawValue)
    }
}

enum ImportConflictBatchResultStatusSnapshot: String, Equatable, Hashable {
    case skipped = "Skipped"
    case keptBoth = "Kept both"
    case replaced = "Replaced"
    case queuedForPerItem = "Queued for per item"
    case pending = "Pending"
    case failed = "Failed"

    var title: String {
        L10n.string(rawValue)
    }
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
            riskSummary: L10n.string("Waiting for Core preview."),
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
        "replace-confirm replace-confirm"
    }
}

struct ImportConflictBatchPerItemQueue: Equatable {
    var importSessionID: String
    var routes: [ImportConflictBatchPerItemRoute]

    var summary: String {
        L10n.plural("import.conflict.per-item-queue-summary", count: routes.count)
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
            applyBlockedReason: L10n.string("Select at least one conflict."),
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
        copy.reason = L10n.string("Not selected")
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
        if hasEmptyManualConflictBatchScope { return L10n.string("Select at least one conflict.") }
        guard let preview = conflictBatchPreviewReport else { return L10n.string("Checking conflicts...") }
        if preview.applyToAllSimilarConflicts {
            return L10n.format(
                "import.conflict.all-similar-scope-summary",
                preview.duplicateConflictCount,
                preview.sameNameConflictCount
            )
        }
        return L10n.plural("import.conflict.selected-scope-summary", count: Int(preview.includedCount))
    }

    var conflictBatchApplyDisabledReason: String? {
        if isConflictBatchApplying { return L10n.string("Applying...") }
        if hasEmptyManualConflictBatchScope { return L10n.string("Select at least one conflict.") }
        guard let preview = conflictBatchPreviewReport else { return L10n.string("Checking conflicts...") }
        if !preview.canApply {
            return preview.applyBlockedReason ?? L10n.string("Could not prepare conflict strategy.")
        }
        if ImportConflictBatchValidation.actionableIncludedCount(preview: preview) == 0 {
            return L10n.string("All conflicts in this scope are blocked.")
        }
        let replaceConfirmed = isConflictBatchReplaceConfirmed || preview.replaceConfirmationRequired
        guard let request = makeImportConflictBatchApplyRequest(replaceConfirmed: replaceConfirmed),
              ImportConflictBatchValidation.canApply(preview: preview, request: request, isApplying: false) else {
            return L10n.string("Refresh conflict strategy preview.")
        }
        return nil
    }

    var conflictBatchAskPerItemDisabledReason: String? {
        if isConflictBatchApplying { return L10n.string("Applying...") }
        if hasEmptyManualConflictBatchScope { return L10n.string("Select at least one conflict.") }
        guard let preview = conflictBatchPreviewReport else { return L10n.string("Checking conflicts...") }
        if ImportConflictBatchValidation.canAskPerItem(preview: preview, isApplying: false) { return nil }
        if preview.includedCount > 0 {
            return L10n.string("All conflicts in this scope are blocked.")
        }
        return preview.applyBlockedReason ?? L10n.string("Select at least one conflict.")
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
