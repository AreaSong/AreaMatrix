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

struct BatchAITagSuggestionTrigger: View {
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?
    let state: AITagBatchSuggestionState
    let actions: AITagBatchSuggestionActions

    @State private var isPresented = false

    var body: some View {
        Button("AI tag suggestions...") {
            isPresented = true
            actions.load(selectedFiles)
        }
        .disabled(openDisabledReason != nil)
        .help(openDisabledReason ?? "Review AI suggested tags for selected files")
        .sheet(isPresented: $isPresented) {
            BatchAITagSuggestionSheet(
                selectedFiles: selectedFiles,
                state: state,
                actions: actions,
                onClose: { isPresented = false }
            )
        }
        .accessibilityIdentifier("S3-07-C3-07-open-batch-ai-tag-suggestions")
    }

    private var openDisabledReason: String? {
        if selectedCount < 2 { return "Select at least two files" }
        return disabledReason
    }
}

private struct BatchAITagSuggestionSheet: View {
    let selectedFiles: [FileEntrySnapshot]
    let state: AITagBatchSuggestionState
    let actions: AITagBatchSuggestionActions
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review suggested tags for \(selectedFiles.count) files")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Review before adding tags. AI suggestions are not applied until you accept them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            content
            actionBar
        }
        .padding(16)
        .frame(width: 720, alignment: .topLeading)
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { state.isConfirming },
                set: { if !$0 { actions.cancelConfirmation() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Apply tags", action: actions.apply)
            Button("Cancel", role: .cancel, action: actions.cancelConfirmation)
        } message: {
            Text(confirmationMessage)
        }
        .accessibilityIdentifier("S3-07-C3-07-batch-ai-tag-suggestions")
    }

    @ViewBuilder private var content: some View {
        if state.isLoading {
            ProgressView("Loading suggested tags...")
        } else if let review = state.review {
            reviewContent(review)
        } else {
            Text("No AI tag suggestions loaded.")
                .foregroundStyle(.secondary)
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Accept high confidence") {
                actions.selectHighConfidence()
                actions.confirm()
            }
            .disabled(!state.hasHighConfidenceApplyCandidates || state.isApplying || state.isLoading)
            Button("Accept selected", action: actions.confirm)
                .disabled(!state.canApplySelectedSuggestions)
            Button("Reject selected", action: actions.clearSelection)
                .disabled(state.review?.selectedTagCount == 0 || state.isApplying || state.isLoading)
            if case .applied = state {
                Button("Retry apply", action: actions.confirm)
                    .disabled(!state.canApplySelectedSuggestions)
            }
            Button("Cancel") {
                actions.cancel()
                onClose()
            }
        }
    }

    private func reviewContent(_ review: AITagBatchSuggestionReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            impactSummary(review)
            HStack(alignment: .top, spacing: 16) {
                fileList(review)
                    .frame(width: 230, alignment: .topLeading)
                suggestionList(review)
            }
            resultSummary(review)
        }
    }

    private func impactSummary(_ review: AITagBatchSuggestionReview) -> some View {
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

    private func fileList(_ review: AITagBatchSuggestionReview) -> some View {
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

    private func suggestionList(_ review: AITagBatchSuggestionReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(review.files) { file in
                if let report = review.reports[file.id] {
                    reportSection(file: file, report: report, review: review)
                }
            }
        }
    }

    private func reportSection(
        file: FileEntrySnapshot,
        report: AiTagSuggestionReport,
        review: AITagBatchSuggestionReview
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.currentName).font(.callout.weight(.semibold))
            Text("Confidence threshold: \(percent(report.confidenceThreshold))% - \(routeLabel(report.route))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if report.suggestions.isEmpty {
                Text(report.skippedReason.map(skipReasonText) ?? "No tag suggestions for this file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(report.suggestions, id: \.suggestionId) { suggestion in
                suggestionRow(suggestion, fileID: file.id, review: review)
            }
        }
        .padding(.bottom, 6)
    }

    private func suggestionRow(
        _ suggestion: AiTagSuggestion,
        fileID: Int64,
        review: AITagBatchSuggestionReview
    ) -> some View {
        let selected = review.selectedIDsByFileID[fileID]?.contains(suggestion.suggestionId) == true
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Button(selected ? "Reject" : "Add") {
                    actions.toggle(fileID, suggestion.suggestionId)
                }
                .disabled(!AITagSuggestionAction.canApply(suggestion) || state.isApplying)
                Text(suggestion.displayName).font(.callout.weight(.semibold))
                Text("\(percent(suggestion.confidence))%").font(.caption)
                Text(candidateStatusText(suggestion)).foregroundStyle(.secondary)
            }
            Text("Reason: \(suggestion.reason)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func resultSummary(_ review: AITagBatchSuggestionReview) -> some View {
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

    private var confirmationTitle: String {
        "Apply suggested tags to \(state.review?.selectedFileCount ?? 0) files?"
    }

    private var confirmationMessage: String {
        "AreaMatrix will add \(state.review?.selectedTagCount ?? 0) reviewed tags. " +
            "Low confidence tags are excluded, and existing tags will not be duplicated."
    }

    private func fileStatus(_ file: FileEntrySnapshot, review: AITagBatchSuggestionReview) -> String {
        if review.applyFailures[file.id] != nil || (review.applyReports[file.id]?.failedCount ?? 0) > 0 {
            return "failed"
        }
        if review.applyReports[file.id] != nil { return "accepted" }
        return (review.selectedIDsByFileID[file.id]?.isEmpty == false) ? "pending" : "rejected"
    }

    private func routeLabel(_ route: AiTagSuggestionRoute?) -> String {
        switch route {
        case .local:
            return "Local"
        case .remote:
            return "Remote"
        case nil:
            return "No provider"
        }
    }

    private func candidateStatusText(_ suggestion: AiTagSuggestion) -> String {
        if let reason = suggestion.disabledReason { return reason }
        switch suggestion.status {
        case .suggested:
            return "Suggested"
        case .lowConfidence:
            return "Low confidence"
        case .alreadyApplied:
            return "Already applied"
        case .invalid:
            return "Invalid"
        case .blocked:
            return "Blocked"
        }
    }

    private func skipReasonText(_ reason: AiTagSuggestionSkipReason) -> String {
        switch reason {
        case .aiDisabled:
            return "AI tag suggestions are off"
        case .featureDisabled:
            return "Auto tags are off"
        case .providerUnavailable:
            return "AI provider is unavailable"
        case .privacyRule:
            return "Skipped by privacy rule"
        case .noEligibleInput:
            return "No eligible tag context"
        case .callLogUnavailable:
            return "AI call log is unavailable"
        }
    }

    private func percent(_ value: Float) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }
}
