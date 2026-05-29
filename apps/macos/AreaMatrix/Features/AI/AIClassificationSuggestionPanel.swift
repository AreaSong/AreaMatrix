import SwiftUI

struct AIClassificationSuggestionPanel: View {
    @ObservedObject var model: AIClassificationSuggestionPanelModel
    var fileName: String
    var currentPath: String
    var onAccept: () -> Void = {}, onChange: () -> Void = {}, onReject: () -> Void = {}
    var onClassifyManually: () -> Void = {}, onViewCall: () -> Void = {}
    @State private var privacyRuleRoute: AIClassificationPrivacyRuleRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI suggested a category")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            fileSummary
            Text(model.statusText)
                .foregroundStyle(statusTint)
                .accessibilityIdentifier("S3-04-C3-04-status")
            if let suggestion = model.suggestion {
                suggestionContent(suggestion)
            }
            if let failure = model.failure {
                failureContent(failure)
            }
            requestControls
        }
        .padding(16)
        .background(.background)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        .sheet(item: $privacyRuleRoute) { route in
            AIClassificationPrivacyRuleReferenceSheet(
                repoPath: model.repoPath,
                ruleID: route.ruleID
            ) {
                privacyRuleRoute = nil
            }
        }
    }

    private var fileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("File: \(fileName)")
            Text("Current path: \(currentPath)")
            Text("No files will be moved until you confirm.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var requestControls: some View {
        HStack {
            Button("Ask AI for suggestion...") {
                Task { await model.askForSuggestion() }
            }
            .disabled(!model.canAskForSuggestion)
            .accessibilityIdentifier("S3-04-C3-04-ask-ai-suggestion")
            Button("Classify manually", action: onClassifyManually)
            Spacer()
        }
    }

    private var statusTint: Color {
        if model.failure != nil { return .red }
        if model.state.isLoading { return .secondary }
        return .primary
    }

    @ViewBuilder
    private func suggestionContent(_ suggestion: AIClassificationSuggestionState) -> some View {
        switch suggestion.status {
        case .suggested:
            suggestedCard(suggestion)
        case .noSuggestion, .skipped, .unavailable:
            skippedOrUnavailableCard(suggestion)
        }
    }

    private func suggestedCard(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Suggested category: \(suggestion.suggestedCategory ?? "Unknown")")
                    .font(.subheadline.weight(.semibold))
                AISuggestionConfidenceBadge(confidence: suggestion.confidence)
                if let route = suggestion.route {
                    Text(route.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Current category: \(suggestion.currentCategory ?? "None")")
            Text("Reason: \(suggestion.reason ?? "No reason provided.")")
            Text("Used: \(usedContextText(for: suggestion))")
                .foregroundStyle(.secondary)
            Text("Target category: \(suggestion.suggestedCategory ?? "Unknown")")
            HStack {
                Button("Accept", action: onAccept)
                    .disabled(model.acceptDisabledReason != nil || model.state.isLoading)
                Button("Change...", action: onChange)
                    .disabled(model.state.isLoading)
                Button("Reject", action: onReject)
                    .disabled(model.state.isLoading)
            }
            if let acceptDisabledReason = model.acceptDisabledReason {
                Text(acceptDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if suggestion.callLogID != nil {
                Button("View AI call", action: onViewCall)
                    .buttonStyle(.link)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S3-04-C3-04-suggestion-card")
    }

    private func skippedOrUnavailableCard(_ suggestion: AIClassificationSuggestionState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = suggestion.skippedReason {
                Text("Reason: \(skipReasonText(reason))")
            }
            if let ruleID = privacyRuleID(for: suggestion) {
                Text("Privacy rule: \(ruleID)")
                    .foregroundStyle(.secondary)
                Button("View privacy rule") {
                    privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("S3-04-C3-09-view-privacy-rule")
            }
            if suggestion.callLogID != nil {
                Button("View AI call", action: onViewCall)
                    .buttonStyle(.link)
            }
        }
        .accessibilityIdentifier("S3-04-C3-04-skipped-card")
    }

    private func failureContent(_ failure: AISettingsError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(failure.message)
            Text(failure.detail)
                .foregroundStyle(.secondary)
            Text(failure.recovery)
                .font(.caption)
        }
        .accessibilityIdentifier("S3-04-C3-04-error")
    }

    private func privacyRuleID(for suggestion: AIClassificationSuggestionState) -> String? {
        guard suggestion.skippedReason == .privacyRule else { return nil }
        let ruleID = suggestion.privacyRuleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ruleID?.isEmpty == false ? ruleID : nil
    }

    private func usedContextText(for suggestion: AIClassificationSuggestionState) -> String {
        suggestion.usedContext.isEmpty ? "none" : suggestion.usedContext.map(\.label).joined(separator: ", ")
    }

    private func skipReasonText(_ reason: AIClassificationSuggestionSkipReasonState) -> String {
        switch reason {
        case .aiDisabled: "AI classification suggestions are off"
        case .featureDisabled: "AI classification feature is off"
        case .ruleResultConfident: "rule classification is already confident"
        case .noEligibleContext: "no eligible context"
        case .privacyRule: "skipped by privacy rule"
        case .providerUnavailable: "provider unavailable"
        }
    }
}

private struct AIClassificationPrivacyRuleRoute: Identifiable, Equatable {
    var ruleID: String
    var id: String { ruleID }
}

struct AISuggestionConfidenceBadge: View {
    var confidence: Float

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(lowConfidence ? Color.orange.opacity(0.14) : Color.green.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityLabel(label)
    }

    private var label: String { lowConfidence ? "Low confidence \(percent)%" : "Confidence \(percent)%" }
    private var percent: Int { Int((min(max(confidence, 0), 1) * 100).rounded()) }
    private var lowConfidence: Bool { confidence < 0.6 }
}
