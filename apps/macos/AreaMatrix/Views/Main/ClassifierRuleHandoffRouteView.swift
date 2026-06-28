import SwiftUI

struct ClassifierRuleHandoffRouteView: View {
    enum Mode {
        case saveRule
        case impactPreview

        var title: String {
            self == .saveRule ? "Save classifier rule" : "Preview classifier impact"
        }

        var pageID: String {
            self == .saveRule ? "classifier-rule-save" : "classifier-impact-preview"
        }

        var intro: String {
            self == .saveRule
                ? "Review the rule draft before saving it for future imports."
                : "Preview how this rule would affect existing files before applying it."
        }

        var note: String {
            self == .saveRule
                // swiftlint:disable:next line_length
                ? "Saving this rule only affects future classifier behavior and does not undo the current classification."
                : "Previewing impact does not undo the current classification or save a rule."
        }
    }

    let mode: Mode
    let repoPath: String
    let handoff: ClassifierRuleHandoff
    let ruleSaver: any CoreClassifierRuleSaving
    let errorMapper: any CoreErrorMapping
    let onCancel: () -> Void
    let onBack: (ClassifierRuleHandoff) -> Void
    let onPreviewImpact: (ClassifierRuleHandoff) -> Void
    let onSaved: (ClassifierRuleSnapshot) -> Void
    @State private var model: ClassifierRuleSaveSheetModel

    init(
        mode: Mode,
        repoPath: String,
        handoff: ClassifierRuleHandoff,
        ruleSaver: any CoreClassifierRuleSaving = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onCancel: @escaping () -> Void,
        onBack: @escaping (ClassifierRuleHandoff) -> Void,
        onPreviewImpact: @escaping (ClassifierRuleHandoff) -> Void,
        onSaved: @escaping (ClassifierRuleSnapshot) -> Void = { _ in }
    ) {
        self.mode = mode
        self.repoPath = repoPath
        self.handoff = handoff
        self.ruleSaver = ruleSaver
        self.errorMapper = errorMapper
        self.onCancel = onCancel
        self.onBack = onBack
        self.onPreviewImpact = onPreviewImpact
        self.onSaved = onSaved
        _model = State(initialValue: ClassifierRuleSaveSheetModel(handoff: handoff))
    }

    var body: some View {
        if mode == .impactPreview {
            ClassifierImpactPreviewSheet(
                repoPath: repoPath,
                handoff: handoff,
                onCancel: onCancel,
                onBack: onBack
            )
        } else {
            MainFileActionSheetContainer(title: mode.title, pageID: mode.pageID) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(mode.intro).font(.callout).foregroundStyle(.secondary)
                    Text(mode.note).font(.caption).foregroundStyle(.secondary)
                    ClassifierRuleHandoffSummary(handoff: handoff)
                    saveRuleContent
                    actionButtons
                }
            }
            .accessibilityIdentifier("\(mode.pageID)-classifier-rule-route")
        }
    }

    private var actionButtons: some View {
        HStack {
            if mode == .saveRule {
                Button("Preview impact") { onPreviewImpact(model.previewHandoff) }
                    .disabled(model.isSaving || model.hasNoCandidates)
                    .accessibilityIdentifier("classifier-rule-save-preview-impact")
            } else {
                Button("Back") { onBack(handoff) }
            }
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                .disabled(model.isSaving)
            if mode == .saveRule {
                Button(model.primaryActionTitle) {
                    Task { await saveRule() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave)
                .accessibilityIdentifier("classifier-rule-save-save-rule")
            }
        }
    }

    @ViewBuilder
    private var saveRuleContent: some View {
        if model.hasNoCandidates {
            Label("No safe rule suggestion", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            RuleBasisPicker(
                model: $model,
                isDisabled: model.isSaving
            )
            Stepper(value: $model.priority, in: ClassifierRuleSaveSheetModel.priorityRange) {
                Text("Priority \(model.priority)")
            }
            .disabled(model.isSaving)
            RulePreviewCard(lines: model.rulePreviewLines)
            validationAndResult
        }
    }

    @ViewBuilder
    private var validationAndResult: some View {
        if let warning = model.warningMessage {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("classifier-rule-save-rule-warning")
        }
        if let validationMessage = model.validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("classifier-rule-save-validation-error")
        }
        if let failure = model.failure {
            VStack(alignment: .leading, spacing: 4) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                Text(failure.suggestedAction)
                    .font(.caption)
                Text(failure.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .foregroundStyle(.red)
            .accessibilityIdentifier("classifier-rule-save-save-error")
        }
        if let saved = model.savedRule {
            Label(saved.summaryText, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityIdentifier("classifier-rule-save-save-success")
        }
    }

    @MainActor
    private func saveRule() async {
        guard model.canSave else { return }
        model.markSaving()
        do {
            let saved = try await ruleSaver.saveClassifierRule(repoPath: repoPath, rule: model.saveRequest)
            model.markSaved(saved)
            onSaved(saved)
        } catch {
            await model.markFailed(mapError(error))
        }
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

extension ClassifierCorrectionRuleRoute {
    var handoffMode: ClassifierRuleHandoffRouteView.Mode {
        switch self {
        case .saveRule:
            .saveRule
        case .impactPreview:
            .impactPreview
        }
    }
}

private struct ClassifierRuleHandoffSummary: View {
    let handoff: ClassifierRuleHandoff

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(handoff.summaryRows, id: \.label) { row in
                metadataRow(row.label, row.value)
            }
        }
    }
}

private struct RuleBasisPicker: View {
    @Binding var model: ClassifierRuleSaveSheetModel
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rule basis")
                .font(.callout.weight(.semibold))
            ForEach(model.keywordCandidates, id: \.self) { keyword in
                Toggle(isOn: keywordBinding(keyword)) {
                    Text("File name contains: \(keyword)")
                }
                .disabled(isDisabled)
            }
            ForEach(model.extensionCandidates, id: \.self) { ext in
                Toggle(isOn: extensionBinding(ext)) {
                    Text("Extension is: .\(ext)")
                }
                .disabled(isDisabled)
            }
        }
        .accessibilityIdentifier("classifier-rule-save-rule-basis")
    }

    private func keywordBinding(_ keyword: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedKeywords.contains(keyword) },
            set: { model.setKeyword(keyword, isSelected: $0) }
        )
    }

    private func extensionBinding(_ ext: String) -> Binding<Bool> {
        Binding(
            get: { model.selectedExtensions.contains(ext) },
            set: { model.setExtension(ext, isSelected: $0) }
        )
    }
}

private struct RulePreviewCard: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rule preview")
                .font(.callout.weight(.semibold))
            ForEach(lines, id: \.self) { line in
                Text(line).font(.caption)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("classifier-rule-save-rule-preview")
    }
}

private extension ClassifierRuleSnapshot {
    var summaryText: String {
        let keywordText = keywords.isEmpty ? "no keywords" : keywords.joined(separator: ", ")
        let extensionText = extensions.isEmpty ? "no extensions" : extensions.joined(separator: ", ")
        return "Classification rule saved for \(targetCategory): \(keywordText); \(extensionText)."
    }
}

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
        previewer: any CoreClassifierImpactPreviewing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
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
            await model.markFailed(mapError(error))
        }
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
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
