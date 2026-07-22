import SwiftUI

struct DeleteFileConfirmSheet: View {
    let file: FileEntrySnapshot?
    let operation: MainFileDeleteOperation?
    let state: MainFileDeleteState
    let isTrashAvailable: Bool
    let onCancel: () -> Void
    let onConfirm: (Int64, MainFileDeleteOperation) -> Void
    let onCollectDiagnostics: () -> Void
    @State private var isConfirmed = false

    var body: some View {
        MainFileActionSheetContainer(
            title: operation?.title ?? L10n.string("Move File to Trash?"),
            pageID: "delete-file"
        ) {
            if let file, let operation {
                VStack(alignment: .leading, spacing: 12) {
                    Text(operation.message)
                        .foregroundStyle(.secondary)
                    if operation == .moveToTrash {
                        deleteImpactText
                    }
                    metadataRow("Name", file.currentName)
                    metadataRow("Location", file.path)
                    metadataRow("Storage mode", file.storageMode)
                    metadataRow("Status", file.statusDisplay)
                    operationStatus(file: file, operation: operation)
                    Toggle(operation.confirmationText, isOn: $isConfirmed)
                        .disabled(state.isDeleting(fileID: file.id))
                    actionButtons(file: file, operation: operation)
                }
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
    }

    private var deleteImpactText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The file is recoverable from system Trash while Trash retains it.")
            Text("AreaMatrix keeps a deleted metadata record for at least 30 days for traceability.")
            Text("Permanent delete is not available from AreaMatrix.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func operationStatus(file: FileEntrySnapshot, operation: MainFileDeleteOperation) -> some View {
        if state.isDeleting(fileID: file.id) {
            Label(operation.runningTitle, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let failure = state.failure(for: file.id) {
            failureView(failure, operation: operation)
        } else if operation == .moveToTrash, !isTrashAvailable {
            Label(
                "Trash is not available. Handle the file in Finder or collect diagnostics.",
                systemImage: "trash.slash"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    private func failureView(
        _ failure: CoreErrorMappingSnapshot,
        operation: MainFileDeleteOperation
    ) -> some View {
        TintedStatusBanner(
            tint: .yellow,
            cornerRadius: 0,
            fillsWidth: false,
            contentPadding: 10,
            backgroundOpacity: 0.12
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Label(operation.failureTitle, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                Text(failure.userMessage)
                    .font(.caption)
                Text(failure.suggestedAction)
                    .font(.caption)
                Text(failure.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button("Collect Diagnostics...", action: onCollectDiagnostics)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func actionButtons(file: FileEntrySnapshot, operation: MainFileDeleteOperation) -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(state.isDeleting(fileID: file.id))
            Button(actionTitle(file: file, operation: operation), role: .destructive) {
                onConfirm(file.id, operation)
            }
            .disabled(actionDisabled(file: file, operation: operation))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func actionTitle(file: FileEntrySnapshot, operation: MainFileDeleteOperation) -> String {
        state.primaryActionTitle(fileID: file.id, operation: operation)
    }

    private func actionDisabled(file: FileEntrySnapshot, operation: MainFileDeleteOperation) -> Bool {
        if state.isDeleting(fileID: file.id) { return true }
        if !isConfirmed { return true }
        return operation == .moveToTrash && !isTrashAvailable
    }
}

extension BatchAITagSuggestionSheet {
    var confirmationTitle: String {
        L10n.plural(
            "file-actions.ai-tag-suggestion.apply-confirmation",
            count: state.review?.selectedFileCount ?? 0
        )
    }

    var confirmationMessage: String {
        L10n.plural(
            "file-actions.ai-tag-suggestion.apply-message",
            count: state.review?.selectedTagCount ?? 0
        )
    }

    var isAIBlocked: Bool {
        guard let review = state.review else { return false }
        return aiOffReason(in: review) != nil
    }

    func fileStatus(_ file: FileEntrySnapshot, review: AITagBatchSuggestionReview) -> String {
        if review.applyFailures[file.id] != nil || (review.applyReports[file.id]?.failedCount ?? 0) > 0 {
            return "failed"
        }
        if review.applyReports[file.id] != nil { return "accepted" }
        return (review.selectedIDsByFileID[file.id]?.isEmpty == false) ? "pending" : "rejected"
    }

    func routeLabel(_ route: AiTagSuggestionRoute?) -> String {
        switch route {
        case .local:
            L10n.string("Local")
        case .remote:
            L10n.string("Remote")
        case nil:
            L10n.string("No provider")
        }
    }

    func aiOffReason(in review: AITagBatchSuggestionReview) -> AiTagSuggestionSkipReason? {
        review.reports.values.compactMap { report in
            switch report.skippedReason {
            case .aiDisabled, .featureDisabled:
                report.skippedReason
            case .providerUnavailable, .privacyRule, .noEligibleInput, .callLogUnavailable, nil:
                nil
            }
        }.first
    }

    func privacyRuleID(for report: AiTagSuggestionReport) -> String? {
        guard report.skippedReason == .privacyRule else { return nil }
        return normalizedAITagPrivacyRuleID(from: report.privacyRuleId)
    }

    func usedContextText(_ fields: [AiTagSuggestionInputField]) -> String {
        fields.isEmpty ? L10n.string("none") : fields.map(aiTagInputFieldText).joined(separator: ", ")
    }

    func aiTagInputFieldText(_ field: AiTagSuggestionInputField) -> String {
        switch field {
        case .fileName:
            L10n.string("filename")
        case .repoRelativePath:
            L10n.string("repo-relative path")
        case .extractedTextExcerpt:
            L10n.string("extracted text")
        case .aiSummary:
            L10n.string("AI summary")
        case .noteSummary:
            L10n.string("note summary")
        case .existingTags:
            L10n.string("existing tags")
        case .tagRegistry:
            L10n.string("tag registry")
        }
    }

    func mergeText(_ suggestion: AiTagSuggestion) -> String {
        switch suggestion.mergeAction {
        case .createTag:
            L10n.format("file-actions.tag-suggestion.will-create", suggestion.slug)
        case .useExistingTag:
            L10n.format(
                "file-actions.tag-suggestion.will-use-existing",
                suggestion.matchedExistingSlug ?? suggestion.slug
            )
        case .mergeWithExistingTag:
            L10n.format(
                "file-actions.tag-suggestion.merge-existing",
                suggestion.matchedExistingSlug ?? suggestion.slug
            )
        }
    }

    func candidateStatusText(_ suggestion: AiTagSuggestion) -> String {
        if let reason = suggestion.disabledReason { return reason }
        switch suggestion.status {
        case .suggested:
            return L10n.string("Suggested")
        case .lowConfidence:
            return L10n.string("Low confidence")
        case .alreadyApplied:
            return L10n.string("Already applied")
        case .invalid:
            return L10n.string("Invalid")
        case .blocked:
            return L10n.string("Blocked")
        }
    }

    func skipReasonText(_ reason: AiTagSuggestionSkipReason) -> String {
        switch reason {
        case .aiDisabled:
            L10n.string("AI tag suggestions are off")
        case .featureDisabled:
            L10n.string("Auto tags are off")
        case .providerUnavailable:
            L10n.string("AI provider is unavailable")
        case .privacyRule:
            L10n.string("Skipped by privacy rule")
        case .noEligibleInput:
            L10n.string("No eligible tag context")
        case .callLogUnavailable:
            L10n.string("AI call log is unavailable")
        }
    }

    func percent(_ value: Float) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}

struct BatchAITagCallLogRoute: Identifiable {
    let callLogID: Int64
    var id: Int64 {
        callLogID
    }
}
