import Foundation

struct AITagBatchSuggestionReview: Equatable {
    var files: [FileEntrySnapshot]
    var reports: [Int64: AiTagSuggestionReport]
    var selectedIDsByFileID: [Int64: Set<String>]
    var loadFailures: [Int64: CoreErrorMappingSnapshot]
    var applyReports: [Int64: AiTagSuggestionApplyReport] = [:]
    var applyFailures: [Int64: CoreErrorMappingSnapshot] = [:]
    var editSessionsByFileID: [Int64: AITagSuggestionEditSession] = [:]
    var rejectedFeedback: [AITagSuggestionRejectedFeedback] = []

    var selectedFileCount: Int {
        selectedIDsByFileID.filter { !$0.value.isEmpty }.count
    }

    var selectedTagCount: Int {
        selectedIDsByFileID.values.reduce(0) { $0 + $1.count }
    }

    var lowConfidenceExcludedCount: Int {
        reports.values.reduce(0) { count, report in
            count + report.suggestions.filter {
                AITagSuggestionAction.canApply($0) &&
                    $0.confidence < report.confidenceThreshold &&
                    selectedIDsByFileID[report.fileId]?.contains($0.suggestionId) != true
            }.count
        }
    }

    var duplicateCount: Int {
        reports.values.reduce(0) { count, report in
            count + report.suggestions.filter { $0.status == .alreadyApplied }.count
        }
    }

    var invalidCount: Int {
        let selectedInvalidCount = reports.values.reduce(0) { count, report in
            if editSessionsByFileID[report.fileId] != nil { return count }
            let selectedIDs = selectedIDsByFileID[report.fileId] ?? []
            return count + report.suggestions.filter { suggestion in
                selectedIDs.contains(suggestion.suggestionId) &&
                    (suggestion.status == .invalid || suggestion.status == .blocked)
            }.count
        }
        return selectedInvalidCount + editSessionsByFileID.values.reduce(0) { $0 + $1.attentionCount }
    }

    var appliedFileCount: Int {
        applyReports.values.filter { $0.appliedCount > 0 || $0.skippedCount > 0 }.count
    }

    var failedFileCount: Int {
        applyFailures.count + applyReports.values.filter { $0.failedCount > 0 }.count
    }

    var appliedTagCount: Int64 {
        applyReports.values.reduce(Int64(0)) { $0 + $1.appliedCount }
    }

    var failedTagCount: Int64 {
        applyReports.values.reduce(Int64(applyFailures.count)) { $0 + $1.failedCount }
    }

    var canApply: Bool {
        selectedTagCount > 0 && invalidCount == 0
    }

    func applyItems(fileID: Int64) -> [ApplyAiTagSuggestionItem] {
        if let session = editSessionsByFileID[fileID] { return session.applyItems }
        guard let report = reports[fileID], let selected = selectedIDsByFileID[fileID] else { return [] }
        return report.suggestions.compactMap { suggestion in
            guard selected.contains(suggestion.suggestionId), AITagSuggestionAction.canApply(suggestion) else {
                return nil
            }
            return ApplyAiTagSuggestionItem(suggestion: suggestion, editedByUser: false)
        }
    }
}

enum AITagBatchSuggestionState: Equatable {
    case idle
    case loading(AITagBatchSuggestionReview)
    case reviewing(AITagBatchSuggestionReview)
    case confirming(AITagBatchSuggestionReview)
    case applying(AITagBatchSuggestionReview)
    case applied(AITagBatchSuggestionReview)

    var review: AITagBatchSuggestionReview? {
        switch self {
        case let .loading(review), let .reviewing(review), let .confirming(review),
             let .applying(review), let .applied(review):
            review
        case .idle:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isApplying: Bool {
        if case .applying = self { return true }
        return false
    }

    var isConfirming: Bool {
        if case .confirming = self { return true }
        return false
    }

    var canApplySelectedSuggestions: Bool {
        review?.canApply == true && !isLoading && !isApplying
    }

    var hasHighConfidenceApplyCandidates: Bool {
        guard let review else { return false }
        return review.reports.values.contains { report in
            report.suggestions.contains {
                AITagSuggestionAction.canApply($0) && $0.confidence >= report.confidenceThreshold
            }
        }
    }

    var fileIDs: Set<Int64> {
        Set(review?.files.map(\.id) ?? [])
    }
}

struct AITagBatchSuggestionActions {
    let load: ([FileEntrySnapshot]) -> Void
    let retry: () -> Void
    let toggle: (Int64, String) -> Void
    let startEditing: (Int64, String) -> Void
    let cancelEditing: (Int64) -> Void
    let editDisplayName: (Int64, String, String) -> Void
    let editSlug: (Int64, String, String) -> Void
    let regenerateSlug: (Int64, String) -> Void
    let selectHighConfidence: () -> Void
    let clearSelection: () -> Void
    let confirm: () -> Void
    let cancelConfirmation: () -> Void
    let apply: () -> Void
    let cancel: () -> Void
}

extension AITagBatchSuggestionActions {
    static var noop: AITagBatchSuggestionActions {
        AITagBatchSuggestionActions(
            load: { _ in }, retry: {}, toggle: { _, _ in },
            startEditing: { _, _ in }, cancelEditing: { _ in },
            editDisplayName: { _, _, _ in }, editSlug: { _, _, _ in },
            regenerateSlug: { _, _ in },
            selectHighConfidence: {}, clearSelection: {}, confirm: {},
            cancelConfirmation: {}, apply: {}, cancel: {}
        )
    }
}
