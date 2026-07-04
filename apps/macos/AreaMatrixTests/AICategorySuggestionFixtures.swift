@testable import AreaMatrix

extension AIClassificationSuggestionState {
    static func aiCategorySuggestionSuggested(fileID: Int64) -> AIClassificationSuggestionState {
        AIClassificationSuggestionState(
            fileID: fileID,
            status: .suggested,
            currentCategory: "inbox",
            suggestedCategory: "finance/invoices",
            confidence: 0.86,
            reason: "filename and extracted text mention invoice and payment",
            route: .local,
            usedContext: [.fileName, .extension, .repoRelativePath],
            skippedReason: nil,
            privacyRuleID: nil,
            callLogID: 304,
            requiresUserConfirmation: true
        )
    }

    static func aiCategorySuggestionProviderUnavailable(fileID: Int64) -> AIClassificationSuggestionState {
        AIClassificationSuggestionState(
            fileID: fileID,
            status: .unavailable,
            currentCategory: "inbox",
            suggestedCategory: nil,
            confidence: 0,
            reason: nil,
            route: .remote,
            usedContext: [],
            skippedReason: .providerUnavailable,
            privacyRuleID: nil,
            callLogID: 306,
            requiresUserConfirmation: true
        )
    }

    static func aiCategorySuggestionPrivacySkipped(fileID: Int64) -> AIClassificationSuggestionState {
        AIClassificationSuggestionState(
            fileID: fileID,
            status: .skipped,
            currentCategory: "inbox",
            suggestedCategory: nil,
            confidence: 0,
            reason: nil,
            route: nil,
            usedContext: [],
            skippedReason: .privacyRule,
            privacyRuleID: "rule-confidential",
            callLogID: 305,
            requiresUserConfirmation: true
        )
    }
}

extension AiFallbackStatus {
    static func aiCategorySuggestionPrivacySkipped(callLogID: Int64) -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: .privacySkipped,
            category: .skipped,
            title: "Skipped by privacy rule",
            message: "No AI call was made because a privacy rule blocked the available context.",
            retryable: false,
            retryDisabledReason: "Privacy skipped suggestions cannot be retried from this panel.",
            primaryAction: .viewPrivacyRule,
            secondaryAction: .viewCallLog,
            nonAiFallbackAction: .classifyManually,
            route: nil,
            callLogId: callLogID,
            privacyRuleId: "rule-confidential",
            retryAfter: nil
        )
    }

    static func aiCategorySuggestionProviderUnavailable(callLogID: Int64) -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: .providerUnavailable,
            category: .unavailable,
            title: "AI provider is unavailable",
            message: "The configured AI provider cannot return a category suggestion right now.",
            retryable: true,
            retryDisabledReason: "Retry before accepting this suggestion.",
            primaryAction: .retry,
            secondaryAction: .viewCallLog,
            nonAiFallbackAction: .classifyManually,
            route: .remote,
            callLogId: callLogID,
            privacyRuleId: nil,
            retryAfter: nil
        )
    }

    static func aiCategorySuggestionInternalFailure() -> AiFallbackStatus {
        AiFallbackStatus(
            operation: .classificationSuggestion,
            kind: .internalFailure,
            category: .error,
            title: "AI suggestion failed.",
            message: "AreaMatrix could not standardize the AI category fallback state.",
            retryable: false,
            retryDisabledReason: "Retry is unavailable until the failure is resolved.",
            primaryAction: .viewCallLog,
            secondaryAction: nil,
            nonAiFallbackAction: .classifyManually,
            route: nil,
            callLogId: nil,
            privacyRuleId: nil,
            retryAfter: nil
        )
    }
}
