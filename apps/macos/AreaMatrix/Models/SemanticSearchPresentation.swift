import Foundation
import SwiftUI

enum SemanticSearchResultGroup: Equatable {
    case semantic
    case normal
}

struct SemanticSearchRowPresentation: Identifiable, Equatable {
    var id: Int64
    var file: FileEntrySnapshot
    var group: SemanticSearchResultGroup
    var matchSource: String
    var relevance: String
    var matchedReason: String
    var whyThisMatched: String
    var routeLabel: String?
    var alsoMatchedNormalSearch: Bool
    var isFoldedDuplicate: Bool

    var categoryPath: String {
        let pathPrefix = file.path.split(separator: "/").dropLast().joined(separator: "/")
        return pathPrefix.isEmpty ? file.category : pathPrefix
    }

    var modified: String {
        SemanticSearchRowPresentation.dateFormatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(file.updatedAt))
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

struct SemanticSearchDetailPresentation: Equatable {
    var title: String
    var relevance: String
    var matchedReason: String
    var whyThisMatched: String
    var routeLabel: String
    var alsoMatchedNormalSearch: Bool
}

struct SemanticSearchPagingState: Equatable {
    var loadingGroup: SemanticSearchResultGroup?
    var semanticError: CoreErrorMappingSnapshot?
    var normalError: CoreErrorMappingSnapshot?

    init(
        loadingGroup: SemanticSearchResultGroup? = nil,
        semanticError: CoreErrorMappingSnapshot? = nil,
        normalError: CoreErrorMappingSnapshot? = nil
    ) {
        self.loadingGroup = loadingGroup
        self.semanticError = semanticError
        self.normalError = normalError
    }

    var isLoadingSemantic: Bool {
        loadingGroup == .semantic
    }

    var isLoadingNormal: Bool {
        loadingGroup == .normal
    }

    static let idle = SemanticSearchPagingState()
}

struct SemanticSearchFallbackActionPresentation: Identifiable, Equatable {
    var action: AiFallbackAction
    var title: String
    var accessibilityID: String

    var id: AiFallbackAction {
        action
    }
}

struct SemanticSearchFallbackStatus {
    var title: String
    var message: String
    var badge: String
    var badgeTint: Color
    var retryable: Bool
    var retryDisabledReason: String?
    var primaryAction: AiFallbackAction?
    var secondaryAction: AiFallbackAction?
    var nonAiFallbackAction: AiFallbackAction
    var callLogID: Int64?
    var privacyRuleID: String?
    var canBuildSemanticIndex: Bool

    var actions: [AiFallbackAction] {
        [
            primaryAction == .retry ? nil : primaryAction,
            secondaryAction,
            nonAiFallbackAction
        ].compactMap { $0 }.reduce(into: []) { actions, action in
            if isVisible(action), !actions.contains(action) { actions.append(action) }
        }
    }

    var actionPresentations: [SemanticSearchFallbackActionPresentation] {
        actions.map(presentation(for:))
    }

    static func fromCoreStatus(_ status: AiFallbackStatus) -> SemanticSearchFallbackStatus {
        SemanticSearchFallbackStatus(
            title: status.title,
            message: status.message,
            badge: badgeText(kind: status.kind),
            badgeTint: badgeTint(category: status.category),
            retryable: status.retryable,
            retryDisabledReason: status.retryDisabledReason,
            primaryAction: status.primaryAction,
            secondaryAction: status.secondaryAction,
            nonAiFallbackAction: status.nonAiFallbackAction,
            callLogID: status.callLogId,
            privacyRuleID: status.privacyRuleId,
            canBuildSemanticIndex: status.primaryAction == .buildSemanticIndex ||
                status.secondaryAction == .buildSemanticIndex
        )
    }

    static func fromSemanticPage(_ page: SemanticSearchResultPageSnapshot) -> SemanticSearchFallbackStatus {
        let reason = page.fallbackReason ?? .providerUnavailable
        return SemanticSearchFallbackStatus(
            title: reason.title,
            message: page.fallbackMessage ?? reason.message,
            badge: reason.badge,
            badgeTint: reason.badgeTint,
            retryable: reason.retryable,
            retryDisabledReason: reason.retryDisabledReason,
            primaryAction: reason.primaryAction,
            secondaryAction: reason.secondaryAction(callLogID: page.callLogID),
            nonAiFallbackAction: .useNormalSearch,
            callLogID: page.callLogID,
            privacyRuleID: page.privacyRuleID,
            canBuildSemanticIndex: page.canBuildIndex && reason == .semanticIndexNotReady
        )
    }

    func isVisible(_ action: AiFallbackAction) -> Bool {
        switch action {
        case .retry, .retryLater, .openAiSettings, .configureRemoteAi, .viewPrivacyRule, .viewCallLog,
             .buildSemanticIndex, .useNormalSearch:
            true
        case .openLocalModelStatus, .classifyManually:
            false
        }
    }

    func title(for action: AiFallbackAction) -> String {
        switch action {
        case .retry: "Retry"
        case .retryLater: "Retry later"
        case .openAiSettings: "Open AI settings"
        case .openLocalModelStatus: "Open local model status"
        case .configureRemoteAi: "Configure remote AI"
        case .viewPrivacyRule: "View privacy rule"
        case .viewCallLog: "View call log"
        case .buildSemanticIndex: "Build semantic index"
        case .useNormalSearch: "Use normal search"
        case .classifyManually: "Classify manually"
        }
    }

    func accessibilityID(for action: AiFallbackAction) -> String {
        switch action {
        case .retry: "retry"
        case .retryLater: "retry-later"
        case .openAiSettings: "open-ai-settings"
        case .openLocalModelStatus: "open-local-model-status"
        case .configureRemoteAi: "configure-remote-ai"
        case .viewPrivacyRule: "view-privacy-rule"
        case .viewCallLog: "view-call-log"
        case .buildSemanticIndex: "build-semantic-index"
        case .useNormalSearch: "use-normal-search"
        case .classifyManually: "classify-manually"
        }
    }

    func presentation(for action: AiFallbackAction) -> SemanticSearchFallbackActionPresentation {
        SemanticSearchFallbackActionPresentation(
            action: action,
            title: title(for: action),
            accessibilityID: accessibilityID(for: action)
        )
    }

    private static func badgeText(kind: AiFallbackKind) -> String {
        switch kind {
        case .aiDisabled: "AI disabled"
        case .featureDisabled: "Feature disabled"
        case .localModelNotReady: "Local not ready"
        case .remoteNotConfigured: "Remote not configured"
        case .remoteFailed: "Remote failed"
        case .providerUnavailable: "Provider unavailable"
        case .privacySkipped: "Privacy skipped"
        case .semanticIndexNotReady: "Semantic index"
        case .noEligibleInput: "No eligible input"
        case .callLogUnavailable: "Call log unavailable"
        case .normalSearchUnavailable: "Normal search"
        case .rateLimited: "Rate limited"
        case .timeout: "Timeout"
        case .internalFailure: "Internal failure"
        }
    }

    private static func badgeTint(category: AiFallbackCategory) -> Color {
        switch category {
        case .skipped: .blue
        case .disabled, .unavailable: .orange
        case .error: .red
        }
    }
}

extension SemanticSearchResultPageSnapshot {
    var hasMoreSemanticMatches: Bool {
        Int64(semanticMatches.count) < semanticTotalCount
    }

    var hasMoreNormalMatches: Bool {
        Int64(normalMatches.count) < normalTotalCount
    }

    func semanticRows() -> [SemanticSearchRowPresentation] {
        semanticMatches.map(SemanticSearchRowPresentation.init(match:))
    }

    func normalRows(showFoldedDuplicates: Bool) -> [SemanticSearchRowPresentation] {
        normalMatches
            .filter { showFoldedDuplicates || !$0.dedupedBySemantic }
            .map(SemanticSearchRowPresentation.init(match:))
    }

    func detailPresentation(for fileID: Int64) -> SemanticSearchDetailPresentation? {
        guard let match = semanticMatches.first(where: { $0.result.file.id == fileID }) else { return nil }
        return SemanticSearchDetailPresentation(
            title: "From semantic search",
            relevance: String(format: "%.2f", match.relevance),
            matchedReason: match.matchedReason,
            whyThisMatched: match.semanticExplanationText,
            routeLabel: match.route.rawValue,
            alsoMatchedNormalSearch: match.alsoMatchedNormalSearch
        )
    }

    func mergingPage(
        _ next: SemanticSearchResultPageSnapshot,
        group: SemanticSearchResultGroup
    ) -> SemanticSearchResultPageSnapshot {
        var merged = self
        merged.semanticTotalCount = next.semanticTotalCount
        merged.normalTotalCount = next.normalTotalCount
        merged.dedupedNormalCount = next.dedupedNormalCount
        merged.indexStatus = next.indexStatus
        merged.route = next.route
        merged.fallbackReason = next.fallbackReason
        merged.fallbackMessage = next.fallbackMessage
        merged.callLogID = next.callLogID
        merged.privacyRuleID = next.privacyRuleID
        merged.lowConfidence = next.lowConfidence
        switch group {
        case .semantic:
            merged.semanticMatches.append(contentsOf: next.semanticMatches)
        case .normal:
            merged.normalMatches.append(contentsOf: next.normalMatches)
        }
        return merged
    }
}

extension SearchResultPageSnapshot {
    func replacingSemanticPage(_ semanticPage: SemanticSearchResultPageSnapshot) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: semanticPage.query,
            totalCount: semanticPage.visibleTotalCount,
            results: semanticPage.visibleResults,
            diagnostics: diagnostics,
            indexStatus: SearchIndexStatusSnapshot(semanticStatus: semanticPage.indexStatus),
            semanticPage: semanticPage
        )
    }
}

extension SemanticSearchRowPresentation {
    init(match: SemanticSearchMatchSnapshot) {
        id = match.result.file.id
        file = match.result.file
        group = .semantic
        matchSource = "Semantic"
        relevance = String(format: "%.2f", match.relevance)
        matchedReason = match.matchedReason
        whyThisMatched = match.semanticExplanationText
        routeLabel = match.route.rawValue
        alsoMatchedNormalSearch = match.alsoMatchedNormalSearch
        isFoldedDuplicate = false
    }

    init(match: SemanticNormalSearchMatchSnapshot) {
        id = match.result.file.id
        file = match.result.file
        group = .normal
        matchSource = "Normal"
        relevance = "-"
        matchedReason = match.normalReasonText
        whyThisMatched = match.normalExplanationText
        routeLabel = nil
        alsoMatchedNormalSearch = false
        isFoldedDuplicate = match.dedupedBySemantic
    }
}

private extension SemanticSearchMatchSnapshot {
    var semanticExplanationText: String {
        let fields = usedFields.map(\.rawValue).joined(separator: ", ")
        let route = "Route: \(route.rawValue)"
        let reason = matchedReason.isEmpty ? "Semantic result matched the query." : matchedReason
        let duplicate = alsoMatchedNormalSearch ? " Also matched normal search." : ""
        return "\(reason) Fields: \(fields). \(route).\(duplicate)"
    }
}

private extension SemanticNormalSearchMatchSnapshot {
    var normalReasonText: String {
        if let noteSnippet = result.noteSnippet, !noteSnippet.isEmpty {
            return "Note: \(noteSnippet)"
        }
        guard let match = result.matches.first else { return "Stage 2 normal search match" }
        return "\(match.kindDisplayName): \(match.fieldDisplayName) - \(match.snippet)"
    }

    var normalExplanationText: String {
        dedupedBySemantic ? "Folded because the same file is already shown in Semantic matches." : normalReasonText
    }
}

private extension SemanticSearchFallbackReasonSnapshot {
    var title: String {
        switch self {
        case .aiDisabled, .featureDisabled: "Semantic search is unavailable"
        case .providerUnavailable: "Remote AI could not be reached"
        case .privacyRule: "Skipped by privacy rule"
        case .semanticIndexNotReady: "Semantic index is not ready"
        case .callLogUnavailable: "AI call log is unavailable"
        case .noEligibleInput: "No eligible input for semantic search"
        case .normalSearchUnavailable: "Normal search is unavailable"
        case .rateLimited: "Provider rate limit reached"
        case .timeout: "AI request timed out"
        }
    }

    var message: String {
        switch self {
        case .aiDisabled:
            "AI is disabled for this repository. Your files were not changed."
        case .featureDisabled:
            "Semantic search is disabled. Your files were not changed."
        case .providerUnavailable:
            "Remote AI could not be reached. Your files were not changed."
        case .privacyRule:
            "This query matches a privacy rule, so AI was skipped."
        case .semanticIndexNotReady:
            "Semantic index is not ready yet."
        case .callLogUnavailable:
            "AreaMatrix could not record the AI call log. Use normal search while logs recover."
        case .noEligibleInput:
            "No files in this scope are eligible for semantic search."
        case .normalSearchUnavailable:
            "Normal search fallback could not be loaded."
        case .rateLimited:
            "Try again later or use normal search."
        case .timeout:
            "The semantic search request timed out. Your files were not changed."
        }
    }

    var badge: String {
        switch self {
        case .aiDisabled: "AI disabled"
        case .featureDisabled: "Feature disabled"
        case .providerUnavailable: "Provider unavailable"
        case .privacyRule: "Privacy skipped"
        case .semanticIndexNotReady: "Semantic index"
        case .callLogUnavailable: "Call log unavailable"
        case .noEligibleInput: "No eligible input"
        case .normalSearchUnavailable: "Normal search"
        case .rateLimited: "Rate limited"
        case .timeout: "Timeout"
        }
    }

    var badgeTint: Color {
        switch self {
        case .privacyRule:
            .blue
        case .providerUnavailable, .normalSearchUnavailable, .timeout:
            .red
        case .aiDisabled, .featureDisabled, .semanticIndexNotReady, .callLogUnavailable,
             .noEligibleInput, .rateLimited:
            .orange
        }
    }

    var retryable: Bool {
        switch self {
        case .providerUnavailable, .timeout:
            true
        case .aiDisabled, .featureDisabled, .privacyRule, .semanticIndexNotReady, .callLogUnavailable,
             .noEligibleInput, .normalSearchUnavailable, .rateLimited:
            false
        }
    }

    var retryDisabledReason: String? {
        switch self {
        case .aiDisabled:
            "Open AI settings before retrying semantic search."
        case .featureDisabled:
            "Enable Semantic search before retrying."
        case .privacyRule:
            "Retry is disabled because this input was skipped by a privacy rule."
        case .semanticIndexNotReady:
            "Build the semantic index or use normal search."
        case .callLogUnavailable:
            "Retry is disabled until call logging is available."
        case .noEligibleInput:
            "Adjust the query or filters before retrying."
        case .normalSearchUnavailable:
            "Normal search must recover before fallback results can be shown."
        case .rateLimited:
            "Try again later."
        case .providerUnavailable, .timeout:
            nil
        }
    }

    var primaryAction: AiFallbackAction? {
        switch self {
        case .aiDisabled, .featureDisabled:
            .openAiSettings
        case .providerUnavailable, .timeout:
            .retry
        case .privacyRule:
            .viewPrivacyRule
        case .semanticIndexNotReady:
            .buildSemanticIndex
        case .callLogUnavailable:
            .viewCallLog
        case .rateLimited:
            .retryLater
        case .noEligibleInput, .normalSearchUnavailable:
            nil
        }
    }

    func secondaryAction(callLogID: Int64?) -> AiFallbackAction? {
        switch self {
        case .providerUnavailable, .timeout, .callLogUnavailable:
            callLogID == nil ? nil : .viewCallLog
        case .aiDisabled, .featureDisabled, .privacyRule, .semanticIndexNotReady, .noEligibleInput,
             .normalSearchUnavailable, .rateLimited:
            nil
        }
    }
}
