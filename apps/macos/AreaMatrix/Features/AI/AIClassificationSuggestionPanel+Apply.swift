import SwiftUI

struct AIClassificationApplyConfirmationContext: Equatable {
    var targetCategory: String
    var preview: MoveToCategoryPreviewSnapshot
    var moveFile: Bool
}

// swiftlint:disable:next type_name
struct AIClassificationSuggestionPanelApplyRequest: Equatable {
    var targetCategory: String
    var moveFile: Bool
    var rememberRule: Bool
    var suggestion: AIClassificationSuggestionState
    var preview: MoveToCategoryPreviewSnapshot
}

// swiftlint:disable:next type_name
struct AIClassificationSuggestionRejectedFeedback: Equatable {
    var fileID: Int64
    var suggestedCategory: String?
    var callLogID: Int64?

    init(suggestion: AIClassificationSuggestionState) {
        fileID = suggestion.fileID
        suggestedCategory = suggestion.suggestedCategory
        callLogID = suggestion.callLogID
    }

    var message: String {
        L10n.string("Suggestion rejected. Feedback recorded for this review.")
    }

    func matches(_ suggestion: AIClassificationSuggestionState) -> Bool {
        fileID == suggestion.fileID &&
            suggestedCategory == suggestion.suggestedCategory &&
            callLogID == suggestion.callLogID
    }
}

extension AIClassificationSuggestionPanel {
    @ViewBuilder
    func suggestionContent(_ suggestion: AIClassificationSuggestionState) -> some View {
        switch suggestion.status {
        case .suggested:
            suggestedCard(suggestion)
        case .noSuggestion, .skipped, .unavailable:
            skippedOrUnavailableCard(suggestion)
        }
    }

    func suggestedCard(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let rejectedFeedback, rejectedFeedback.matches(suggestion) {
                rejectedContent(rejectedFeedback, suggestion: suggestion)
            } else {
                suggestedReviewContent(suggestion)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-suggestion-card")
        .task(id: previewTaskID(for: suggestion)) {
            requestPreviewIfNeeded(for: suggestion)
        }
        .confirmationDialog(
            "Apply AI category?",
            isPresented: $showApplyConfirmation,
            titleVisibility: .visible,
            presenting: applyConfirmationContext(for: suggestion)
        ) { context in
            Button("Apply category") {
                onApply(AIClassificationSuggestionPanelApplyRequest(
                    targetCategory: context.targetCategory,
                    moveFile: context.moveFile,
                    rememberRule: rememberRule,
                    suggestion: suggestion,
                    preview: context.preview
                ))
            }
            Button("Cancel", role: .cancel) {}
        } message: { context in
            Text(applyConfirmationMessage(context))
        }
    }

    @ViewBuilder
    func rejectedContent(
        _ feedback: AIClassificationSuggestionRejectedFeedback,
        suggestion: AIClassificationSuggestionState
    ) -> some View {
        Label(feedback.message, systemImage: "checkmark.circle")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-reject-feedback")
        if let callLogID = suggestion.callLogID {
            Button("View AI call") {
                onViewCall(callLogID)
            }
            .buttonStyle(.link)
        }
    }

    func suggestedReviewContent(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.format(
                    "ai.classification.suggestedCategory",
                    suggestion.suggestedCategory ?? L10n.string("Unknown")
                ))
                .font(.subheadline.weight(.semibold))
                AISuggestionConfidenceBadge(confidence: suggestion.confidence)
                if let route = suggestion.route {
                    Text(route.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(L10n.format(
                "ai.classification.currentCategory",
                suggestion.currentCategory ?? L10n.string("None")
            ))
            Text(L10n.format(
                "ai.classification.reason",
                suggestion.reason ?? L10n.string("No reason provided.")
            ))
            Text("Used: \(usedContextText(for: suggestion))")
                .foregroundStyle(.secondary)
            Text(L10n.format(
                "ai.classification.targetCategory",
                suggestion.suggestedCategory ?? L10n.string("Unknown")
            ))
            applyPreviewContent(for: suggestion)
            Toggle("Create rule from this correction", isOn: $rememberRule)
                .disabled(model.state.isLoading || moveState.isMoving(fileID: suggestion.fileID))
            applyButtons(for: suggestion)
            applyFailureRecovery(for: suggestion)
            if let callLogID = suggestion.callLogID {
                Button("View AI call") {
                    onViewCall(callLogID)
                }
                .buttonStyle(.link)
            }
        }
    }

    func applyButtons(for suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(primaryApplyTitle(for: suggestion), action: acceptSuggestion)
                    .disabled(acceptDisabledReason(for: suggestion) != nil)
                Button("Change...", action: onChange)
                    .disabled(model.state.isLoading)
                Button("Reject") {
                    rejectSuggestion(suggestion)
                }
                .disabled(model.state.isLoading)
            }
            if let acceptDisabledReason = acceptDisabledReason(for: suggestion) {
                Text(acceptDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func skippedOrUnavailableCard(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = suggestion.skippedReason {
                Text("Reason: \(skipReasonText(reason))")
            }
            if let ruleID = privacyRuleID(for: suggestion) {
                Text("Privacy rule: \(ruleID)")
                    .foregroundStyle(.secondary)
                Button("View privacy rule") {
                    privacyRuleRoute = aiPrivacyRulesPrivacyRuleRoute(ruleID: ruleID)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("ai-category-suggestion-ai-privacy-rules-core-view-privacy-rule")
            }
            if let callLogID = suggestion.callLogID {
                Button("View AI call") {
                    onViewCall(callLogID)
                }
                .buttonStyle(.link)
            }
        }
        .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-skipped-card")
    }
}

extension AIClassificationSuggestionPanel {
    @ViewBuilder
    func applyPreviewContent(for suggestion: AIClassificationSuggestionState) -> some View {
        if let category = targetCategory(for: suggestion) {
            let request = MainFileCategoryMovePreviewRequest(fileID: suggestion.fileID, targetCategory: category)
            VStack(alignment: .leading, spacing: 4) {
                Text("Current path: \(currentPath)")
                if let preview = moveState.preview(for: request) {
                    Text("Target path: \(preview.targetPath)")
                    Text(applyPreviewPolicyText(preview))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if moveState.isChecking(request) {
                    Text("Target path: Checking destination...")
                } else {
                    applyPreviewPendingOrFailure(for: suggestion, targetCategory: category)
                }
                Text("No files will be moved until you confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-target-path-preview")
        }
    }

    @ViewBuilder
    func applyPreviewPendingOrFailure(
        for suggestion: AIClassificationSuggestionState,
        targetCategory: String
    ) -> some View {
        if let failure = moveState.failure(for: suggestion.fileID, targetCategory: targetCategory),
           moveState.failureOperation(for: suggestion.fileID, targetCategory: targetCategory) == .preview {
            applyFailureView(failure, title: L10n.string("Target path preview failed."))
        } else {
            Text("Target path: Waiting for Core preview...")
        }
    }

    @ViewBuilder
    func applyFailureRecovery(for suggestion: AIClassificationSuggestionState) -> some View {
        if let category = targetCategory(for: suggestion),
           let failure = moveState.failure(for: suggestion.fileID, targetCategory: category),
           moveState.failureOperation(for: suggestion.fileID, targetCategory: category) == .correction {
            applyFailureView(failure, title: L10n.string("Apply failed."))
            HStack {
                Button("Retry apply") {
                    showApplyConfirmation = true
                }
                .disabled(applyConfirmationContext(for: suggestion) == nil)
                Button("Classify manually", action: onClassifyManually)
                if let callLogID = suggestion.callLogID {
                    Button("View call log") {
                        onViewCall(callLogID)
                    }
                }
            }
            .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-apply-failure-actions")
        }
    }

    func applyFailureView(_ failure: CoreErrorMappingSnapshot, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(failure.userMessage)
                .font(.caption)
            Text(failure.suggestedAction)
                .font(.caption)
        }
        .foregroundStyle(.red)
        .accessibilityIdentifier("ai-category-suggestion-ai-classification-suggestion-apply-error")
    }
}

extension AIClassificationSuggestionPanel {
    func acceptDisabledReason(for suggestion: AIClassificationSuggestionState) -> String? {
        if model.state.isLoading { return L10n.string("Suggestion is still loading.") }
        if let reason = model.acceptDisabledReason { return reason }
        guard let category = targetCategory(for: suggestion) else { return L10n.string("Target category is missing.") }
        let request = MainFileCategoryMovePreviewRequest(fileID: suggestion.fileID, targetCategory: category)
        if moveState.isChecking(request) { return L10n.string("Checking target path before apply.") }
        if moveState.isMoving(fileID: suggestion.fileID) { return L10n.string("Applying AI category...") }
        if let operation = moveState.failureOperation(for: suggestion.fileID, targetCategory: category),
           operation == .preview {
            return L10n.string("Resolve the target path preview failure before accepting.")
        }
        if moveState.preview(for: request) == nil {
            return L10n.string("Target path preview is required before accepting.")
        }
        return nil
    }

    func primaryApplyTitle(for suggestion: AIClassificationSuggestionState) -> String {
        moveState.isMoving(fileID: suggestion.fileID) ? L10n.string("Applying...") : L10n.string("Accept")
    }

    @discardableResult
    func rejectSuggestion(_ suggestion: AIClassificationSuggestionState) -> AIClassificationSuggestionRejectedFeedback {
        let feedback = AIClassificationSuggestionRejectedFeedback(suggestion: suggestion)
        rejectedFeedback = feedback
        return feedback
    }

    func requestPreviewIfNeeded(for suggestion: AIClassificationSuggestionState) {
        guard let category = targetCategory(for: suggestion) else { return }
        let request = MainFileCategoryMovePreviewRequest(fileID: suggestion.fileID, targetCategory: category)
        guard moveState.preview(for: request) == nil,
              !moveState.isChecking(request),
              moveState.failureOperation(for: suggestion.fileID, targetCategory: category) != .preview else { return }
        onPreview(category)
    }

    func acceptSuggestion() {
        showApplyConfirmation = true
    }

    func previewTaskID(for suggestion: AIClassificationSuggestionState) -> String {
        "\(suggestion.fileID)-\(targetCategory(for: suggestion) ?? "none")"
    }

    func targetCategory(for suggestion: AIClassificationSuggestionState) -> String? {
        let category = suggestion.suggestedCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        return category?.isEmpty == false ? category : nil
    }

    func applyConfirmationContext(
        for suggestion: AIClassificationSuggestionState
    ) -> AIClassificationApplyConfirmationContext? {
        guard let category = targetCategory(for: suggestion),
              acceptDisabledReason(for: suggestion) == nil else { return nil }
        let request = MainFileCategoryMovePreviewRequest(fileID: suggestion.fileID, targetCategory: category)
        guard let preview = moveState.preview(for: request) else { return nil }
        return AIClassificationApplyConfirmationContext(
            targetCategory: category,
            preview: preview,
            moveFile: preview.willMoveFile
        )
    }

    func applyPreviewPolicyText(_ preview: MoveToCategoryPreviewSnapshot) -> String {
        if preview.indexOnly {
            return L10n.string("AreaMatrix will update category metadata and change log only.")
        }
        if preview.nameConflictResolved {
            return L10n.format(
                "Existing user files will not be overwritten. AreaMatrix will use %@.",
                preview.targetName
            )
        }
        return L10n.string("AreaMatrix will update the category and move the file to the target folder.")
    }

    func applyConfirmationMessage(_ context: AIClassificationApplyConfirmationContext) -> String {
        let action = context.moveFile
            ? L10n.string("AreaMatrix will update the category and move the file to the target folder.")
            : L10n.string("AreaMatrix will update the category metadata and change log.")
        let conflict = context.preview.nameConflictResolved
            ? L10n.format("ai.classification.conflictTargetName", context.preview.targetName)
            : L10n.string(" Existing user files will not be overwritten.")
        return L10n.format(
            "ai.classification.applyConfirmation",
            action,
            conflict,
            context.preview.targetPath
        )
    }

    func privacyRuleID(for suggestion: AIClassificationSuggestionState) -> String? {
        guard suggestion.skippedReason == .privacyRule else { return nil }
        let ruleID = suggestion.privacyRuleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ruleID?.isEmpty == false ? ruleID : nil
    }

    func usedContextText(for suggestion: AIClassificationSuggestionState) -> String {
        suggestion.usedContext.isEmpty ? L10n.string("none") : suggestion.usedContext.map(\.label)
            .joined(separator: ", ")
    }

    func skipReasonText(_ reason: AIClassificationSuggestionSkipReasonState) -> String {
        switch reason {
        case .aiDisabled: L10n.string("AI classification suggestions are off")
        case .featureDisabled: L10n.string("AI classification feature is off")
        case .ruleResultConfident: L10n.string("rule classification is already confident")
        case .noEligibleContext: L10n.string("no eligible context")
        case .privacyRule: L10n.string("skipped by privacy rule")
        case .providerUnavailable: L10n.string("provider unavailable")
        }
    }
}
