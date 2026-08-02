import SwiftUI

struct ClassifierRuleHandoffRouteView: View {
    enum Mode {
        case saveRule
        case impactPreview

        var title: String {
            self == .saveRule ? L10n.string("Save classifier rule") : L10n.string("Preview classifier impact")
        }

        var pageID: String {
            self == .saveRule ? "classifier-rule-save" : "classifier-impact-preview"
        }

        var intro: String {
            self == .saveRule
                ? L10n.string("Review the rule draft before saving it for future imports.")
                : L10n.string("Preview how this rule would affect existing files before applying it.")
        }

        var note: String {
            self == .saveRule
                ? L10n.string("file-actions.classifier-rule.futureOnlyNote")
                : L10n.string("file-actions.classifier-rule.previewOnlyNote")
        }
    }

    let mode: Mode
    let repoPath: String
    let handoff: ClassifierRuleHandoff
    let ruleSaver: any CoreClassifierRuleSaving
    let previewer: any CoreClassifierImpactPreviewing
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
        ruleSaver: any CoreClassifierRuleSaving,
        previewer: any CoreClassifierImpactPreviewing,
        errorMapper: any CoreErrorMapping,
        onCancel: @escaping () -> Void,
        onBack: @escaping (ClassifierRuleHandoff) -> Void,
        onPreviewImpact: @escaping (ClassifierRuleHandoff) -> Void,
        onSaved: @escaping (ClassifierRuleSnapshot) -> Void = { _ in }
    ) {
        self.mode = mode
        self.repoPath = repoPath
        self.handoff = handoff
        self.ruleSaver = ruleSaver
        self.previewer = previewer
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
                previewer: previewer,
                errorMapper: errorMapper,
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
                Button(L10n.string("Preview impact")) { onPreviewImpact(model.previewHandoff) }
                    .disabled(model.isSaving || model.hasNoCandidates)
                    .accessibilityIdentifier("classifier-rule-save-preview-impact")
            } else {
                Button(L10n.string("Back")) { onBack(handoff) }
            }
            Spacer()
            Button(L10n.string("Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
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
            Label(L10n.string("No safe rule suggestion"), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            RuleBasisPicker(
                model: $model,
                isDisabled: model.isSaving
            )
            Stepper(value: $model.priority, in: ClassifierRuleSaveSheetModel.priorityRange) {
                Text(L10n.format("file-actions.classifier-rule.priority", Int64(model.priority)))
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
            await model.markFailed(errorMapper.mapError(error))
        }
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
            Text(L10n.string("Rule basis"))
                .font(.callout.weight(.semibold))
            ForEach(model.keywordCandidates, id: \.self) { keyword in
                Toggle(isOn: keywordBinding(keyword)) {
                    Text(L10n.format("file-actions.classifier-rule.filename-contains", keyword))
                }
                .disabled(isDisabled)
            }
            ForEach(model.extensionCandidates, id: \.self) { ext in
                Toggle(isOn: extensionBinding(ext)) {
                    Text(L10n.format("file-actions.classifier-rule.extension-is", ext))
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
        NeutralSummaryPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Rule preview"))
                    .font(.callout.weight(.semibold))
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.caption)
                }
            }
        }
        .accessibilityIdentifier("classifier-rule-save-rule-preview")
    }
}

private extension ClassifierRuleSnapshot {
    var summaryText: String {
        let keywordText = keywords.isEmpty ? L10n.string("no keywords") : keywords.joined(separator: ", ")
        let extensionText = extensions.isEmpty ? L10n.string("no extensions") : extensions.joined(separator: ", ")
        return L10n.format(
            "file-actions.classifier-rule.saved-summary",
            targetCategory,
            keywordText,
            extensionText
        )
    }
}
