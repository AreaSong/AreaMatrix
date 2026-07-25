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
        MainFileActionSheetContainer(title: L10n.string("Preview rule impact"), pageID: "classifier-impact-preview") {
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
            metadataRow(
                L10n.string("Move preference"),
                model.moveFiles ? L10n.string("Move files to new category folders") : L10n.string("Metadata only")
            )
            Toggle(L10n.string("Move files to new category folders"), isOn: moveFilesBinding)
                .disabled(model.loadState.isLoading)
                .accessibilityIdentifier("classifier-impact-preview-move-files")
        }
    }

    @ViewBuilder
    private var previewState: some View {
        if model.loadState.isLoading {
            Label(L10n.string("Previewing impact..."), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("classifier-impact-preview-loading")
        }
        if let failure = model.loadState.failure {
            VStack(alignment: .leading, spacing: 4) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                Text(failure.suggestedAction).font(.caption)
                Button(L10n.string("Retry preview")) { Task { await refreshPreview() } }
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
                Text(L10n.plural("file-actions.classifier-impact.matching-files", count: report.affectedFileCount))
                Text(L10n.plural("file-actions.classifier-impact.will-change", count: report.willUpdateCount))
                Text(L10n.plural("file-actions.classifier-impact.already-correct", count: report.alreadyCorrectCount))
                Text(
                    L10n.plural(
                        "file-actions.classifier-impact.need-review",
                        count: report.needsReviewCount + report.conflictCount
                    )
                )
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
            Picker(L10n.string("Rows"), selection: $model.filter) {
                ForEach(ClassifierImpactPreviewFilter.allCases) { filter in
                    Text(filter.displayName).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("classifier-impact-preview-filter")

            Table(model.filteredSamples) {
                TableColumn(L10n.string("File")) { sample in
                    Text(sample.path).lineLimit(1)
                }
                TableColumn(L10n.string("Current category")) { sample in
                    Text(sample.currentCategory)
                }
                TableColumn(L10n.string("New category")) { sample in
                    Text(sample.newCategory)
                }
                TableColumn(L10n.string("Action")) { sample in
                    Text(actionText(for: sample))
                }
                TableColumn(L10n.string("Status")) { sample in
                    statusCell(sample)
                }
            }
            .frame(minHeight: 220)
            .accessibilityIdentifier("classifier-impact-preview-impact-table")
        }
    }

    private var actionButtons: some View {
        HStack {
            Button(L10n.string("Back")) { onBack(model.handoff) }
                .disabled(model.loadState.isLoading)
            Spacer()
            Button(L10n.string("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
            Button(L10n.string("Save rule only")) {}
                .disabled(true)
                .help(L10n.string("Save the rule before applying it to existing files."))
            Button(L10n.string("Save and apply to existing files")) {}
                .keyboardShortcut(.defaultAction)
                .disabled(true)
                .help(
                    model.primaryApplyDisabledReason
                        ?? L10n.string("Review the impact preview before applying this rule.")
                )
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
        return reasons.isEmpty ? L10n.string("Classifier matcher") : reasons
    }

    private func statusCell(_ sample: RuleImpactSampleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(sample.status.displayName).font(.caption.weight(.semibold))
            if let reason = sample.reason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
