import SwiftUI

struct ClassifierRuleListView: View {
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.classifierRuleEditor.rules) { rule in
                Button { model.selectClassifierRule(ruleID: rule.ruleID) } label: {
                    HStack {
                        ruleLabel(rule)
                        Spacer()
                        ruleStatus(rule)
                    }
                }
                .buttonStyle(.plain)
                .padding(8)
                .background(ruleListBackground(rule), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("classifier-rule-editor-rule-row-\(rule.slug)")
            }
        }
        .frame(width: 210, alignment: .topLeading)
    }

    private func ruleLabel(_ rule: ClassifierRuleRecordSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.classifierRuleEditor.displayName(for: rule))
                .font(.callout.weight(.semibold))
            Text(rule.slug)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func ruleStatus(_ rule: ClassifierRuleRecordSnapshot) -> some View {
        if rule.isDefault {
            Text(L10n.string("default")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        if model.classifierRuleEditor.selectedRuleID == rule.ruleID,
           model.classifierRuleEditor.hasDirtyDraft {
            Text(L10n.string("dirty")).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
        }
    }

    private func ruleListBackground(_ rule: ClassifierRuleRecordSnapshot) -> Color {
        if model.classifierRuleEditor.selectedRuleID == rule.ruleID {
            return Color.accentColor.opacity(0.12)
        }
        return Color.secondary.opacity(0.06)
    }
}

struct ClassifierRuleDetailView: View {
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        if let draft = model.classifierRuleEditor.draft {
            VStack(alignment: .leading, spacing: 12) {
                fields(draft)
                chips(title: L10n.string("Extensions"), values: draft.extensions, isExtension: true)
                chips(title: L10n.string("Keywords"), values: draft.keywords, isExtension: false)
                riskConfirmation
                validation(draft)
                actions
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Text(L10n.string("Select a category or create a new category."))
                .foregroundStyle(.secondary)
        }
    }

    private func fields(_ draft: ClassifierRuleEditorDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(L10n.string("slug"), text: draftBinding(\.slug))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("classifier-rule-editor-slug")
            TextField(L10n.string("display name"), text: draftBinding(\.displayName))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("classifier-rule-editor-display-name")
            TextField(L10n.string("description"), text: draftBinding(\.description))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("classifier-rule-editor-description")
            if let fallback = model.classifierRuleEditor.fallbackDisplayName(for: draft) {
                Text(L10n.format("settings.classifier.fallbackPreview", fallback))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("classifier-rule-editor-fallback-preview")
            }
            Stepper(value: priorityBinding, in: ClassifierRuleEditorValidation.priorityRange) {
                Text(L10n.format("settings.classifier.priorityValue", draft.priority))
            }
            TextField(L10n.string("naming template"), text: draftBinding(\.namingTemplate))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("classifier-rule-editor-naming-template")
        }
        .disabled(model.classifierRuleEditor.isBusy)
    }

    private func chips(title: String, values: [String], isExtension: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.semibold))
            chipRows(values: values, isExtension: isExtension)
            HStack {
                TextField(isExtension ? ".pdf" : "invoice", text: pendingBinding(isExtension: isExtension))
                    .textFieldStyle(.roundedBorder)
                Button(isExtension ? L10n.string("Add extension") : L10n.string("Add keyword")) {
                    addChip(isExtension: isExtension)
                }
                .disabled(model.classifierRuleEditor.isBusy)
            }
        }
    }

    private func chipRows(values: [String], isExtension: Bool) -> some View {
        FlowLikeChipStack(values: values) { value in
            Button {
                removeChip(value, isExtension: isExtension)
            } label: {
                Label(value, systemImage: "xmark.circle")
            }
            .accessibilityIdentifier("classifier-rule-editor-remove-\(isExtension ? "extension" : "keyword")-\(value)")
        }
    }

    @ViewBuilder
    private func validation(_ draft: ClassifierRuleEditorDraft) -> some View {
        if !draft.previewConfirmed {
            Label(
                L10n.string("Impact summary required before Save; existing files are not moved or deleted."),
                systemImage: "eye"
            )
            .foregroundStyle(.orange)
            .accessibilityIdentifier("classifier-rule-editor-impact-required")
        }
        ForEach(draft.validationErrors) { error in
            Label(error.displayText, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(L10n.string("Preview impact")) { model.requestClassifierRuleImpactSummary() }
                .disabled(model.classifierRuleEditor.isBusy)
                .accessibilityIdentifier("classifier-rule-editor-preview-impact")
            Button(L10n.string("Validate")) { model.validateClassifierRuleDraft() }
                .disabled(model.classifierRuleEditor.isBusy)
                .accessibilityIdentifier("classifier-rule-editor-validate")
            Button(L10n.string("Save")) { Task { await model.saveClassifierRuleDraft() } }
                .disabled(!model.classifierRuleEditor.canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("classifier-rule-editor-save")
            Button(L10n.string("Revert")) { model.revertClassifierRuleDraft() }
                .disabled(!model.classifierRuleEditor.canRevert)
                .accessibilityIdentifier("classifier-rule-editor-revert")
            Button(L10n.string("Delete category...")) { model.requestDeleteSelectedClassifierRule() }
                .disabled(!model.classifierRuleEditor.canDeleteSelectedRule)
                .accessibilityIdentifier("classifier-rule-editor-delete-category")
        }
    }

    @ViewBuilder
    private var riskConfirmation: some View {
        if let removal = model.classifierRuleEditor.pendingMatcherRemoval {
            matcherImpactSummary(removal)
        } else if let deletion = model.classifierRuleEditor.pendingDeleteConfirmation {
            categoryDeleteConfirmation(deletion)
        } else if model.classifierRuleEditor.isShowingImpactSummary {
            draftImpactSummary
        }
    }

    private func matcherImpactSummary(_ removal: ClassifierRuleMatcherRemoval) -> some View {
        riskPanel(identifier: "classifier-rule-editor-matcher-impact-summary") {
            Label(L10n.string("Impact summary"), systemImage: "eye")
                .font(.callout.weight(.semibold))
            Text(matcherImpactCopy(removal))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.string("Cancel")) { model.cancelClassifierRuleRiskConfirmation() }
                Button(L10n.string("Confirm removal")) { model.confirmClassifierRuleImpactSummary() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("classifier-rule-editor-confirm-matcher-removal")
            }
        }
    }

    private func categoryDeleteConfirmation(_ deletion: ClassifierRuleDeleteConfirmation) -> some View {
        riskPanel(identifier: "classifier-rule-editor-delete-category-confirmation") {
            Label(L10n.string("Delete category?"), systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text(L10n
                .string("This removes the category from classifier.yaml. Existing files are not moved or deleted."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(categoryDeleteDetail(deletion))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.string("Cancel")) { model.cancelClassifierRuleRiskConfirmation() }
                Button(L10n.string("Confirm delete")) { Task { await model.confirmDeleteSelectedClassifierRule() } }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("classifier-rule-editor-confirm-delete-category")
            }
        }
    }

    private var draftImpactSummary: some View {
        riskPanel(identifier: "classifier-rule-editor-impact-summary") {
            Label(L10n.string("Impact summary"), systemImage: "eye")
                .font(.callout.weight(.semibold))
            Text(L10n.string("Saving this classifier draft updates future classification rules only."))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(L10n.string("Existing files are not moved, deleted, renamed, or reclassified from this page."))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button(L10n.string("Cancel")) { model.cancelClassifierRuleRiskConfirmation() }
                Button(L10n.string("Confirm summary")) { model.confirmClassifierRuleImpactSummary() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("classifier-rule-editor-confirm-impact-summary")
            }
        }
    }

    private func riskPanel(
        identifier: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        TintedStatusBanner(tint: .orange, contentPadding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

private extension ClassifierRuleDetailView {
    func draftBinding(_ keyPath: WritableKeyPath<ClassifierRuleEditorDraft, String>) -> Binding<String> {
        Binding(
            get: { model.classifierRuleEditor.draft?[keyPath: keyPath] ?? "" },
            set: { value in
                guard var draft = model.classifierRuleEditor.draft else { return }
                draft[keyPath: keyPath] = value
                model.updateClassifierRuleDraft(draft)
            }
        )
    }

    var priorityBinding: Binding<Int64> {
        Binding(
            get: { model.classifierRuleEditor.draft?.priority ?? 0 },
            set: { value in
                guard var draft = model.classifierRuleEditor.draft else { return }
                draft.priority = value
                model.updateClassifierRuleDraft(draft)
            }
        )
    }

    func pendingBinding(isExtension: Bool) -> Binding<String> {
        Binding(
            get: {
                isExtension ? model.classifierRuleEditor.pendingExtension : model.classifierRuleEditor.pendingKeyword
            },
            set: { value in
                if isExtension {
                    model.classifierRuleEditor.pendingExtension = value
                } else {
                    model.classifierRuleEditor.pendingKeyword = value
                }
            }
        )
    }

    func addChip(isExtension: Bool) {
        if isExtension {
            model.addClassifierRuleExtension(model.classifierRuleEditor.pendingExtension)
            model.classifierRuleEditor.pendingExtension = ""
        } else {
            model.addClassifierRuleKeyword(model.classifierRuleEditor.pendingKeyword)
            model.classifierRuleEditor.pendingKeyword = ""
        }
    }

    func removeChip(_ value: String, isExtension: Bool) {
        if isExtension {
            model.requestRemoveClassifierRuleExtension(value)
        } else {
            model.requestRemoveClassifierRuleKeyword(value)
        }
    }

    func matcherImpactCopy(_ removal: ClassifierRuleMatcherRemoval) -> String {
        L10n.format(
            "settings.classifier.matcherRemovalImpact",
            removal.kind.rawValue,
            removal.value,
            removal.categoryName
        )
    }

    func categoryDeleteDetail(_ deletion: ClassifierRuleDeleteConfirmation) -> String {
        L10n.format(
            "settings.classifier.categoryDeleteDetail",
            deletion.categoryName,
            deletion.replacementCategory ?? L10n.string("none")
        )
    }
}

private struct FlowLikeChipStack<Content: View>: View {
    let values: [String]
    let content: (String) -> Content

    var body: some View {
        if values.isEmpty {
            Text(L10n.string("No custom classifier rules yet"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(values, id: \.self) { value in
                    content(value)
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}
