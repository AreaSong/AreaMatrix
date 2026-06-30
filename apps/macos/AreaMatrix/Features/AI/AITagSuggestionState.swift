import Foundation

enum AITagSuggestionState: Equatable {
    case idle
    case loading(fileID: Int64, previous: AiTagSuggestionReport?)
    case loaded(fileID: Int64, AiTagSuggestionReport, Set<String>)
    case rejected(fileID: Int64, AiTagSuggestionReport, AITagSuggestionRejectedFeedback)
    case editing(fileID: Int64, AiTagSuggestionReport, AITagSuggestionEditSession)
    case applying(fileID: Int64, report: AiTagSuggestionReport, selectedIDs: Set<String>)
    case applyingEdited(fileID: Int64, report: AiTagSuggestionReport, session: AITagSuggestionEditSession)
    case editApplied(fileID: Int64, AiTagSuggestionReport, AiTagSuggestionApplyReport, AITagSuggestionEditSession)
    case applied(fileID: Int64, AiTagSuggestionReport, AiTagSuggestionApplyReport, Set<String>)
    case failed(fileID: Int64, CoreErrorMappingSnapshot, previous: AiTagSuggestionReport?)
}

extension AITagSuggestionState {
    var report: AiTagSuggestionReport? {
        switch self {
        case let .loaded(_, report, _), let .rejected(_, report, _), let .loading(_, report?),
             let .editing(_, report, _), let .applying(_, report, _), let .applyingEdited(_, report, _),
             let .applied(_, report, _, _), let .editApplied(_, report, _, _),
             let .failed(_, _, report?):
            report
        case .idle, .loading, .failed:
            nil
        }
    }

    var selectedIDs: Set<String> {
        switch self {
        case let .loaded(_, _, selected), let .applying(_, _, selected), let .applied(_, _, _, selected):
            selected
        case let .editing(_, _, session), let .applyingEdited(_, _, session), let .editApplied(_, _, _, session):
            session.selectedIDs
        case .idle, .loading, .rejected, .failed:
            []
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var isApplying: Bool {
        switch self {
        case .applying, .applyingEdited:
            true
        case .idle, .loading, .loaded, .rejected, .editing, .applied, .editApplied, .failed:
            false
        }
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(_, mapping, _) = self else { return nil }
        return mapping
    }

    var appliedReport: AiTagSuggestionApplyReport? {
        switch self {
        case let .applied(_, _, report, _), let .editApplied(_, _, report, _):
            report
        case .idle, .loading, .loaded, .rejected, .editing, .applying, .applyingEdited, .failed:
            nil
        }
    }

    var editSession: AITagSuggestionEditSession? {
        switch self {
        case let .editing(_, _, session), let .applyingEdited(_, _, session), let .editApplied(_, _, _, session):
            session
        case .idle, .loading, .loaded, .rejected, .applying, .applied, .failed:
            nil
        }
    }

    var rejectedFeedback: AITagSuggestionRejectedFeedback? {
        guard case let .rejected(_, _, feedback) = self else { return nil }
        return feedback
    }

    var fileID: Int64? {
        switch self {
        case let .loading(fileID, _), let .loaded(fileID, _, _), let .rejected(fileID, _, _),
             let .editing(fileID, _, _), let .applying(fileID, _, _), let .applyingEdited(fileID, _, _),
             let .applied(fileID, _, _, _), let .editApplied(fileID, _, _, _), let .failed(fileID, _, _):
            fileID
        case .idle:
            nil
        }
    }

    var hasHighConfidenceApplyCandidates: Bool {
        guard let report else { return false }
        return report.suggestions.contains {
            AITagSuggestionAction.canApply($0) && $0.confidence >= report.confidenceThreshold
        }
    }

    var canApplySelectedSuggestions: Bool {
        if let editSession { return editSession.canApply }
        return !AITagSuggestionAction.selectedApplyItems(in: self).isEmpty
    }

    var canEditSelectedSuggestions: Bool {
        !AITagSuggestionAction.selectedApplyItems(in: self).isEmpty
    }
}
