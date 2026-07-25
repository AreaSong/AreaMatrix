import SwiftUI

struct BatchDeletePreviewSummary: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let preview: BatchDeletePreviewReportSnapshot
    let showsDetails: Bool
    let onToggleDetails: () -> Void

    var body: some View {
        let presentation = BatchDeletePreviewReportPresentation(report: preview)
        NeutralSummaryPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(localizer.resolve(presentation.trashSummaryText))
                Text(localizer.resolve(presentation.indexOnlySummaryText))
                Text(L10n.plural("file-actions.delete.preview.missing-items", count: Int(preview.missingCount)))
                Text(localizer.resolve(presentation.blockedSummaryText))
                Text(localizer.resolve(presentation.undoSummaryText))
                Text(localizer.resolve(presentation.safetySummaryText))
                availabilityWarnings
                if let reason = preview.applyBlockedReason, !reason.isEmpty {
                    Text(reason).foregroundStyle(.secondary)
                }
                Button(showsDetails ? "Hide details" : "View details", action: onToggleDetails)
                previewRows
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var availabilityWarnings: some View {
        if !preview.trashAvailable {
            Label(
                [
                    L10n.string("Trash is not available for this location."),
                    L10n.string("AreaMatrix will not permanently delete these files.")
                ].joined(separator: " "),
                systemImage: "trash.slash"
            )
        }
        if preview.blockedCount > 0 {
            Label(L10n.string("Blocked items will be left unchanged."), systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var previewRows: some View {
        if showsDetails {
            BatchDeletePreviewTable(items: preview.items)
        } else {
            BatchDeletePreviewTable(items: Array(preview.items.prefix(8)))
            if preview.items.count > 8 {
                Text(L10n.plural("file-actions.delete.preview.more-items", count: preview.items.count - 8))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BatchDeleteResultSummary: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let result: BatchDeleteReportSnapshot
    let showsDetails: Bool
    let onToggleDetails: () -> Void

    var body: some View {
        let presentation = BatchDeleteReportPresentation(report: result)
        NeutralSummaryPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(localizer.resolve(presentation.successSummaryText))
                Text(localizer.resolve(presentation.skippedSummaryText))
                Text(localizer.resolve(presentation.failedSummaryText))
                Text(localizer.resolve(presentation.undoSummaryText))
                failedDetails
            }
        }
    }

    @ViewBuilder
    private var failedDetails: some View {
        if result.failedCount > 0 {
            Button(L10n.string("View details"), action: onToggleDetails)
            if showsDetails {
                ForEach(result.itemResults.filter { $0.status == .failed }) { item in
                    Text(
                        L10n.format(
                            "file-actions.common.file-error",
                            item.fileID,
                            item.error ?? L10n.string("Failed")
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BatchDeletePreviewTable: View {
    let items: [BatchDeletePreviewItemSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                Text(rowText(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func rowText(_ item: BatchDeletePreviewItemSnapshot) -> String {
        let name = item.currentName ?? item.currentPath ?? L10n.format("File %lld", item.fileID)
        let reason = item.reason.map { " - \($0)" } ?? ""
        return "\(name): \(item.status.displayName)\(reason)"
    }
}

extension BatchAITagSuggestionSheet {
    @ViewBuilder var content: some View {
        if state.isLoading {
            ProgressView("Loading suggested tags...")
        } else if let review = state.review {
            reviewContent(review)
        } else {
            Text(L10n.string("No AI tag suggestions loaded."))
                .foregroundStyle(.secondary)
        }
    }

    func reviewContent(_ review: AITagBatchSuggestionReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reason = aiOffReason(in: review) {
                aiOffNotice(reason)
            }
            impactSummary(review)
            rejectedFeedbackSummary(review)
            HStack(alignment: .top, spacing: 16) {
                fileList(review)
                    .frame(width: 230, alignment: .topLeading)
                suggestionList(review)
            }
            resultSummary(review)
        }
    }

    func impactSummary(_ review: AITagBatchSuggestionReview) -> some View {
        NeutralSummaryPanel {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.format(
                    "file-actions.ai-tag-suggestion.impact",
                    review.selectedFileCount,
                    review.selectedTagCount
                ))
                Text(L10n.string("Low confidence tags are excluded."))
                Text(L10n.string("Existing tags will not be duplicated."))
                Text(
                    L10n.format(
                        "file-actions.ai-tag-suggestion.excluded",
                        review.lowConfidenceExcludedCount,
                        review.duplicateCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                if review.invalidCount > 0 {
                    Text(
                        L10n.plural(
                            "file-actions.ai-tag-suggestion.invalid-or-blocked",
                            count: review.invalidCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        }
    }

    func rejectedFeedbackSummary(_ review: AITagBatchSuggestionReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(review.rejectedFeedback) { feedback in
                Label(feedback.message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("ai-tag-suggestions-ai-tags-suggestion-batch-reject-feedback")
    }

    func fileList(_ review: AITagBatchSuggestionReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("Files")).font(.caption).foregroundStyle(.secondary)
            ForEach(review.files) { file in
                Text(
                    L10n.format(
                        "file-actions.tag-suggestion.file-status",
                        file.currentName,
                        fileStatus(file, review: review)
                    )
                )
                .font(.caption)
            }
            ForEach(review.loadFailures.sorted(by: { $0.key < $1.key }), id: \.key) { fileID, failure in
                Text(L10n.format("file-actions.common.file-error", fileID, failure.userMessage))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    func suggestionList(_ review: AITagBatchSuggestionReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(review.files) { file in
                if let report = review.reports[file.id] {
                    reportSection(file: file, report: report, review: review)
                }
            }
        }
    }

    func reportSection(
        file: FileEntrySnapshot,
        report: AiTagSuggestionReport,
        review: AITagBatchSuggestionReview
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.currentName).font(.callout.weight(.semibold))
            Text(
                L10n.format(
                    "file-actions.tag-suggestion.confidence-threshold",
                    Int64(percent(report.confidenceThreshold)),
                    routeLabel(report.route)
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(L10n.format("file-actions.tag-suggestion.used-fields", usedContextText(report.usedContext)))
                .font(.caption)
                .foregroundStyle(.secondary)
            if report.suggestions.isEmpty {
                Text(report.skippedReason.map(skipReasonText) ?? L10n.string("No tag suggestions for this file."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            reportTraceLinks(report)
            ForEach(report.suggestions, id: \.suggestionId) { suggestion in
                suggestionRow(suggestion, fileID: file.id, review: review)
            }
        }
        .padding(.bottom, 6)
    }

    func suggestionRow(
        _ suggestion: AiTagSuggestion,
        fileID: Int64,
        review: AITagBatchSuggestionReview
    ) -> some View {
        let selected = review.selectedIDsByFileID[fileID]?.contains(suggestion.suggestionId) == true
        let canAdd = AITagSuggestionAction.canApply(suggestion)
        let draft = review.editSessionsByFileID[fileID]?.drafts.first { $0.suggestionID == suggestion.suggestionId }
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Button(selected ? L10n.string("Reject") : L10n.string("Add")) {
                    actions.toggle(fileID, suggestion.suggestionId)
                }
                .disabled(state.isApplying || (!selected && !canAdd))
                Button(L10n.string("Edit")) {
                    actions.startEditing(fileID, suggestion.suggestionId)
                }
                .disabled(state.isApplying || suggestion.status == .alreadyApplied)
                Text(suggestion.displayName).font(.callout.weight(.semibold))
                Text(
                    L10n.format(
                        "file-actions.common.percentage",
                        Int64(percent(suggestion.confidence))
                    )
                ).font(.caption)
                Text(candidateStatusText(suggestion)).foregroundStyle(.secondary)
            }
            Text(L10n.format("file-actions.tag-suggestion.reason", suggestion.reason))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(mergeText(suggestion))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let draft {
                editRow(draft, fileID: fileID)
            }
        }
    }

    func editRow(_ draft: AITagSuggestionEditDraft, fileID: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(L10n.string("Display name"), text: Binding(
                get: { draft.displayName },
                set: { actions.editDisplayName(fileID, draft.suggestionID, $0) }
            ))
            HStack {
                TextField(L10n.string("Slug"), text: Binding(
                    get: { draft.slug },
                    set: { actions.editSlug(fileID, draft.suggestionID, $0) }
                ))
                Button(L10n.string("Regenerate")) {
                    actions.regenerateSlug(fileID, draft.suggestionID)
                }
                Button(L10n.string("Cancel edit")) {
                    actions.cancelEditing(fileID)
                }
            }
            if draft.status.preventsApply {
                Text(draft.status.message ?? draft.status.label)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(state.isApplying)
    }

    func aiOffNotice(_ reason: AiTagSuggestionSkipReason) -> some View {
        NeutralSummaryPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(skipReasonText(reason))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.string("AI tag suggestions are not generated while this setting is off."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.string("Open AI settings"), action: onOpenAISettings)
                    Button(L10n.string("Close")) {
                        actions.cancel()
                        onClose()
                    }
                }
            }
        }
    }

    func reportTraceLinks(_ report: AiTagSuggestionReport) -> some View {
        HStack {
            if let ruleID = privacyRuleID(for: report) {
                Button(L10n.string("View privacy rule")) {
                    privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("ai-tag-suggestions-ai-privacy-rules-core-view-batch-privacy-rule")
            }
            if let callLogID = report.callLogId {
                Button(L10n.string("View AI call")) {
                    callLogRoute = BatchAITagCallLogRoute(callLogID: callLogID)
                }
                .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder func resultSummary(_ review: AITagBatchSuggestionReview) -> some View {
        if case .applied = state {
            VStack(alignment: .leading, spacing: 4) {
                Text("Applied to \(review.appliedFileCount) files, failed on \(review.failedFileCount) files.")
                Text("Applied \(review.appliedTagCount) tags, failed \(review.failedTagCount) tags.")
                Text("Invalid \(review.invalidCount), duplicate \(review.duplicateCount).")
                ForEach(review.applyFailures.sorted(by: { $0.key < $1.key }), id: \.key) { fileID, failure in
                    Text(L10n.format("file-actions.common.file-error", fileID, failure.userMessage))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
