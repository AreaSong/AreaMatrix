import Foundation

enum ImportConflictBatchConflictTypeSnapshot: String, Equatable, Hashable {
    case duplicateHash = "DuplicateHash"
    case sameNameDifferentContent = "SameNameDifferentContent"

    var titleMessage: LocalizedMessage {
        switch self {
        case .duplicateHash: L10n.message("Duplicate content")
        case .sameNameDifferentContent: L10n.message("Same name, different content")
        }
    }
}

enum ImportConflictBatchStrategySnapshot: String, Equatable, Hashable {
    case skip = "Skip"
    case keepBoth = "KeepBoth"
    case replace = "Replace"
    case askPerItem = "AskPerItem"

    var titleMessage: LocalizedMessage {
        switch self {
        case .skip: L10n.message("Skip")
        case .keepBoth: L10n.message("Keep both")
        case .replace: L10n.message("Replace")
        case .askPerItem: L10n.message("Ask per item")
        }
    }
}

enum ImportConflictBatchPreviewStatusSnapshot: String, Equatable, Hashable {
    case ready = "Ready"
    case pending = "Pending"
    case needsConfirmation = "Needs confirmation"
    case blocked = "Blocked"
    case failed = "Failed"

    var titleMessage: LocalizedMessage {
        switch self {
        case .ready: L10n.message("Ready")
        case .pending: L10n.message("Pending")
        case .needsConfirmation: L10n.message("Needs confirmation")
        case .blocked: L10n.message("Blocked")
        case .failed: L10n.message("Failed")
        }
    }
}

enum ImportConflictBatchResultStatusSnapshot: String, Equatable, Hashable {
    case skipped = "Skipped"
    case keptBoth = "Kept both"
    case replaced = "Replaced"
    case queuedForPerItem = "Queued for per item"
    case pending = "Pending"
    case failed = "Failed"

    var titleMessage: LocalizedMessage {
        switch self {
        case .skipped: L10n.message("Skipped")
        case .keptBoth: L10n.message("Kept both")
        case .replaced: L10n.message("Replaced")
        case .queuedForPerItem: L10n.message("Queued for per item")
        case .pending: L10n.message("Pending")
        case .failed: L10n.message("Failed")
        }
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
    var conflictBatchPerItemSummary: LocalizedMessage? {
        conflictBatchPerItemQueue.map { L10n.pluralMessage(
            "import.conflict.per-item-queue-summary",
            count: $0.routes.count
        ) }
    }

    var conflictBatchPerItemRouteLabels: [String] {
        conflictBatchPerItemQueue?.routes.map(\.routeLabel) ?? []
    }

    var conflictBatchScopeSummary: LocalizedMessage {
        if hasEmptyManualConflictBatchScope { return L10n.message("Select at least one conflict.") }
        guard let preview = conflictBatchPreviewReport else { return L10n.message("Checking conflicts...") }
        if preview.applyToAllSimilarConflicts {
            return L10n.message(
                "import.conflict.all-similar-scope-summary",
                arguments: [
                    .integer64(preview.duplicateConflictCount),
                    .integer64(preview.sameNameConflictCount)
                ]
            )
        }
        return L10n.pluralMessage("import.conflict.selected-scope-summary", count: preview.includedCount)
    }

    var conflictBatchApplyDisabledReason: AppDisplayText? {
        if isConflictBatchApplying { return .localized(L10n.message("Applying...")) }
        if hasEmptyManualConflictBatchScope { return .localized(L10n.message("Select at least one conflict.")) }
        guard let preview = conflictBatchPreviewReport else { return .localized(L10n.message("Checking conflicts...")) }
        if !preview.canApply {
            return preview.applyBlockedReason.map(ImportConflictBatchDisplayText.fromCore)
                ?? .localized(L10n.message("Could not prepare conflict strategy."))
        }
        if ImportConflictBatchValidation.actionableIncludedCount(preview: preview) == 0 {
            return .localized(L10n.message("All conflicts in this scope are blocked."))
        }
        let replaceConfirmed = isConflictBatchReplaceConfirmed || preview.replaceConfirmationRequired
        guard let request = makeImportConflictBatchApplyRequest(replaceConfirmed: replaceConfirmed),
              ImportConflictBatchValidation.canApply(preview: preview, request: request, isApplying: false) else {
            return .localized(L10n.message("Refresh conflict strategy preview."))
        }
        return nil
    }

    var conflictBatchAskPerItemDisabledReason: AppDisplayText? {
        if isConflictBatchApplying { return .localized(L10n.message("Applying...")) }
        if hasEmptyManualConflictBatchScope { return .localized(L10n.message("Select at least one conflict.")) }
        guard let preview = conflictBatchPreviewReport else { return .localized(L10n.message("Checking conflicts...")) }
        if ImportConflictBatchValidation.canAskPerItem(preview: preview, isApplying: false) { return nil }
        if preview.includedCount > 0 {
            return .localized(L10n.message("All conflicts in this scope are blocked."))
        }
        return preview.applyBlockedReason.map(ImportConflictBatchDisplayText.fromCore)
            ?? .localized(L10n.message("Select at least one conflict."))
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

enum ImportConflictBatchDisplayText {
    static func fromCore(_ value: String) -> AppDisplayText {
        knownMessages[value].map(AppDisplayText.localized)
            ?? L10n.verbatim(value, reason: .technicalDetail)
    }

    private static let knownMessages: [String: LocalizedMessage] = [
        "No selected conflicts can be applied": L10n.message("No selected conflicts can be applied"),
        "One or more import conflicts are blocked": L10n.message("One or more import conflicts are blocked"),
        "Conflict is queued for per-item handling": L10n.message("Conflict is queued for per-item handling"),
        "Conflict is already resolved": L10n.message("Conflict is already resolved"),
        "Previous apply attempt failed": L10n.message("Previous apply attempt failed"),
        "Index-only staging cannot be batch imported": L10n.message("Index-only staging cannot be batch imported"),
        "Index-only staging cannot replace an existing file":
            L10n.message("Index-only staging cannot replace an existing file"),
        "Replace requires an active target file": L10n.message("Replace requires an active target file"),
        "Index-only target cannot be replaced": L10n.message("Index-only target cannot be replaced"),
        "Trash unavailable": L10n.message("Trash unavailable"),
        "This row cannot be processed safely": L10n.message("This row cannot be processed safely"),
        "Incoming duplicate stays in staging; existing file is unchanged":
            L10n.message("Incoming duplicate stays in staging; existing file is unchanged"),
        "Incoming file will be imported with a conflict-free name":
            L10n.message("Incoming file will be imported with a conflict-free name"),
        "Existing file will move to recoverable storage before incoming file takes its place":
            L10n.message("Existing file will move to recoverable storage before incoming file takes its place"),
        "Conflict will stay staged for per-item handling":
            L10n.message("Conflict will stay staged for per-item handling"),
        "Waiting for Core preview.": L10n.message("Waiting for Core preview."),
        "Select at least one conflict.": L10n.message("Select at least one conflict."),
        "Not selected": L10n.message("Not selected")
    ]
}
