import SwiftUI

struct ClassifierImpactPreviewSheet: View {
    let repoPath: String
    let handoff: ClassifierRuleHandoff
    let previewer: any CoreClassifierImpactPreviewing
    let errorMapper: any CoreErrorMapping
    let onCancel: () -> Void
    let onBack: (ClassifierRuleHandoff) -> Void
    @State private var model: ClassifierImpactPreviewSheetModel

    init(
        repoPath: String,
        handoff: ClassifierRuleHandoff,
        previewer: any CoreClassifierImpactPreviewing = AppCoreServices.classifierImpactPreviewer,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        onCancel: @escaping () -> Void,
        onBack: @escaping (ClassifierRuleHandoff) -> Void
    ) {
        self.repoPath = repoPath
        self.handoff = handoff
        self.previewer = previewer
        self.errorMapper = errorMapper
        self.onCancel = onCancel
        self.onBack = onBack
        _model = State(initialValue: ClassifierImpactPreviewSheetModel(handoff: handoff))
    }

    var body: some View {
        MainFileActionSheetContainer(title: "Preview rule impact", pageID: "classifier-impact-preview") {
            VStack(alignment: .leading, spacing: 12) {
                ruleSummary
                previewState
                if let report = model.loadState.report {
                    impactSummary(report)
                    impactTable
                }
                actionButtons
            }
        }
        .task(id: previewTaskKey) { await refreshPreview() }
        .accessibilityIdentifier("classifier-impact-preview-classifier-impact-preview")
    }

    private var previewTaskKey: String {
        [
            model.request.mode.rawValue,
            model.request.rule.targetCategory,
            model.request.rule.keywords.joined(separator: ","),
            model.request.rule.extensions.joined(separator: ","),
            "\(model.request.rule.priority)",
            model.request.moveFiles ? "move" : "metadata"
        ].joined(separator: ":")
    }

    private var ruleSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow("Rule", model.ruleSummary)
            metadataRow("Applies to", model.appliesSummary)
            metadataRow("Move preference", model.moveFiles ? "Move files to new category folders" : "Metadata only")
            Toggle("Move files to new category folders", isOn: moveFilesBinding)
                .disabled(model.loadState.isLoading)
                .accessibilityIdentifier("classifier-impact-preview-move-files")
        }
    }

    @ViewBuilder
    private var previewState: some View {
        if model.loadState.isLoading {
            Label("Previewing impact...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("classifier-impact-preview-loading")
        }
        if let failure = model.loadState.failure {
            VStack(alignment: .leading, spacing: 4) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                Text(failure.suggestedAction).font(.caption)
                Button("Retry preview") { Task { await refreshPreview() } }
                    .accessibilityIdentifier("classifier-impact-preview-retry-preview")
            }
            .foregroundStyle(.red)
            .accessibilityIdentifier("classifier-impact-preview-preview-error")
        }
    }

    private func impactSummary(_ report: RuleImpactReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let empty = model.emptyStateText {
                Text(empty).foregroundStyle(.secondary)
            } else {
                Text("\(report.affectedFileCount) existing files match this rule")
                Text("\(report.willUpdateCount) will change category")
                Text("\(report.alreadyCorrectCount) already match target category")
                Text("\(report.needsReviewCount + report.conflictCount) need review")
            }
            if report.warningRequired, let warning = report.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let reason = model.primaryApplyDisabledReason {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("classifier-impact-preview-apply-disabled-reason")
            }
        }
        .accessibilityIdentifier("classifier-impact-preview-impact-summary")
    }

    private var impactTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Rows", selection: $model.filter) {
                ForEach(ClassifierImpactPreviewFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("classifier-impact-preview-filter")

            Table(model.filteredSamples) {
                TableColumn("File") { sample in
                    Text(sample.path).lineLimit(1)
                }
                TableColumn("Current category") { sample in
                    Text(sample.currentCategory)
                }
                TableColumn("New category") { sample in
                    Text(sample.newCategory)
                }
                TableColumn("Action") { sample in
                    Text(actionText(for: sample))
                }
                TableColumn("Status") { sample in
                    statusCell(sample)
                }
            }
            .frame(minHeight: 220)
            .accessibilityIdentifier("classifier-impact-preview-impact-table")
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("Back") { onBack(model.handoff) }
                .disabled(model.loadState.isLoading)
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
            Button("Save rule only") {}
                .disabled(true)
                .help("Save the rule before applying it to existing files.")
            Button("Save and apply to existing files") {}
                .keyboardShortcut(.defaultAction)
                .disabled(true)
                .help(model.primaryApplyDisabledReason ?? "Review the impact preview before applying this rule.")
        }
    }

    private var moveFilesBinding: Binding<Bool> {
        Binding(
            get: { model.moveFiles },
            set: { model.setMoveFiles($0) }
        )
    }

    @MainActor
    private func refreshPreview() async {
        model.markLoading()
        do {
            let report = try await previewer.previewClassifierRuleImpact(repoPath: repoPath, request: model.request)
            model.markLoaded(report)
        } catch {
            await model.markFailed(errorMapper.mapError(error))
        }
    }

    private func actionText(for sample: RuleImpactSampleSnapshot) -> String {
        let reasons = sample.matchReasons.map(\.displayLabel).joined(separator: ", ")
        return reasons.isEmpty ? "Classifier matcher" : reasons
    }

    private func statusCell(_ sample: RuleImpactSampleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sample.status.rawValue).font(.caption.weight(.semibold))
            if let reason = sample.reason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
