import SwiftUI

struct BatchDeletePreviewSummary: View {
    let preview: BatchDeletePreviewReportSnapshot
    let showsDetails: Bool
    let onToggleDetails: () -> Void

    var body: some View {
        let presentation = BatchDeletePreviewReportPresentation(report: preview)
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.trashSummaryText)
            Text(presentation.indexOnlySummaryText)
            Text("\(preview.missingCount) missing items can be removed from the index")
            Text(presentation.blockedSummaryText)
            Text(presentation.undoSummaryText)
            Text(presentation.safetySummaryText)
            availabilityWarnings
            if let reason = preview.applyBlockedReason, !reason.isEmpty {
                Text(reason).foregroundStyle(.secondary)
            }
            Button(showsDetails ? "Hide details" : "View details", action: onToggleDetails)
            previewRows
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var availabilityWarnings: some View {
        if !preview.trashAvailable {
            Label(
                [
                    "Trash is not available for this location.",
                    "AreaMatrix will not permanently delete these files in Stage 2."
                ].joined(separator: " "),
                systemImage: "trash.slash"
            )
        }
        if preview.blockedCount > 0 {
            Label("Blocked items will be left unchanged.", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var previewRows: some View {
        if showsDetails {
            BatchDeletePreviewTable(items: preview.items)
        } else {
            BatchDeletePreviewTable(items: Array(preview.items.prefix(8)))
            if preview.items.count > 8 {
                Text("+\(preview.items.count - 8) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BatchDeleteResultSummary: View {
    let result: BatchDeleteReportSnapshot
    let showsDetails: Bool
    let onToggleDetails: () -> Void

    var body: some View {
        let presentation = BatchDeleteReportPresentation(report: result)
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.successSummaryText)
            Text(presentation.skippedSummaryText)
            Text(presentation.failedSummaryText)
            Text(presentation.undoSummaryText)
            failedDetails
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var failedDetails: some View {
        if result.failedCount > 0 {
            Button("View details", action: onToggleDetails)
            if showsDetails {
                ForEach(result.itemResults.filter { $0.status == .failed }) { item in
                    Text("File \(item.fileID): \(item.error ?? "Failed")")
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
        let name = item.currentName ?? item.currentPath ?? "File \(item.fileID)"
        let reason = item.reason.map { " - \($0)" } ?? ""
        return "\(name): \(item.status.rawValue)\(reason)"
    }
}

extension BatchAITagSuggestionSheet {
    @ViewBuilder var content: some View {
        if state.isLoading {
            ProgressView("Loading suggested tags...")
        } else if let review = state.review {
            reviewContent(review)
        } else {
            Text("No AI tag suggestions loaded.")
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
        VStack(alignment: .leading, spacing: 4) {
            Text("\(review.selectedFileCount) files will receive \(review.selectedTagCount) tags.")
            Text("Low confidence tags are excluded.")
            Text("Existing tags will not be duplicated.")
            Text("Excluded: \(review.lowConfidenceExcludedCount) low confidence, \(review.duplicateCount) duplicate.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if review.invalidCount > 0 {
                Text("\(review.invalidCount) invalid or blocked suggestions must be rejected before applying.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    func rejectedFeedbackSummary(_ review: AITagBatchSuggestionReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(review.rejectedFeedback) { feedback in
                Label(feedback.message, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("S3-07-C3-07-batch-reject-feedback")
    }

    func fileList(_ review: AITagBatchSuggestionReview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Files").font(.caption).foregroundStyle(.secondary)
            ForEach(review.files) { file in
                Text("\(file.currentName): \(fileStatus(file, review: review))")
                    .font(.caption)
            }
            ForEach(review.loadFailures.sorted(by: { $0.key < $1.key }), id: \.key) { fileID, failure in
                Text("File \(fileID): \(failure.userMessage)")
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
            Text("Confidence threshold: \(percent(report.confidenceThreshold))% - \(routeLabel(report.route))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Used fields: \(usedContextText(report.usedContext))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if report.suggestions.isEmpty {
                Text(report.skippedReason.map(skipReasonText) ?? "No tag suggestions for this file.")
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
                Button(selected ? "Reject" : "Add") {
                    actions.toggle(fileID, suggestion.suggestionId)
                }
                .disabled(state.isApplying || (!selected && !canAdd))
                Button("Edit") {
                    actions.startEditing(fileID, suggestion.suggestionId)
                }
                .disabled(state.isApplying || suggestion.status == .alreadyApplied)
                Text(suggestion.displayName).font(.callout.weight(.semibold))
                Text("\(percent(suggestion.confidence))%").font(.caption)
                Text(candidateStatusText(suggestion)).foregroundStyle(.secondary)
            }
            Text("Reason: \(suggestion.reason)")
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
            TextField("Display name", text: Binding(
                get: { draft.displayName },
                set: { actions.editDisplayName(fileID, draft.suggestionID, $0) }
            ))
            HStack {
                TextField("Slug", text: Binding(
                    get: { draft.slug },
                    set: { actions.editSlug(fileID, draft.suggestionID, $0) }
                ))
                Button("Regenerate") {
                    actions.regenerateSlug(fileID, draft.suggestionID)
                }
                Button("Cancel edit") {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(skipReasonText(reason))
                .font(.subheadline.weight(.semibold))
            Text("AI tag suggestions are not generated while this setting is off.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open AI settings", action: onOpenAISettings)
                Button("Close") {
                    actions.cancel()
                    onClose()
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder func reportTraceLinks(_ report: AiTagSuggestionReport) -> some View {
        HStack {
            if let ruleID = privacyRuleID(for: report) {
                Button("View privacy rule") {
                    privacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
                }
                .buttonStyle(.link)
                .accessibilityIdentifier("S3-07-C3-09-view-batch-privacy-rule")
            }
            if let callLogID = report.callLogId {
                Button("View AI call") {
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
                    Text("File \(fileID): \(failure.userMessage)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}
