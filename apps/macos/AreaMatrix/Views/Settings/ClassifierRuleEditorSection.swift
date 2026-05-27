import SwiftUI

struct ClassifierRuleEditorSection: View {
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        ClassifierSettingsSection(title: "可视化分类规则") {
            VStack(alignment: .leading, spacing: 12) {
                header
                status
                content
            }
            .accessibilityIdentifier("S2-19-classifier-rule-editor")
        }
    }

    private var header: some View {
        HStack {
            Button { model.createClassifierRule() } label: {
                Label("New category", systemImage: "plus")
            }
            .disabled(model.classifierRuleEditor.isBusy)
            .accessibilityIdentifier("S2-19-new-category")

            Button {
                Task { await model.loadClassifierRuleEditor() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(model.classifierRuleEditor.isBusy)
            Spacer()
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.classifierRuleEditor.loadState {
        case .idle, .loaded:
            if let warning = model.classifierRuleEditor.warning {
                Label(warning, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        case .loading:
            ProgressView("Loading classifier rules...")
                .controlSize(.small)
                .accessibilityIdentifier("S2-19-loading-classifier-rules")
        case let .failed(mapping):
            classifierRuleEditorError(mapping)
        }
        if case let .failed(mapping) = model.classifierRuleEditor.saveState {
            classifierRuleEditorError(mapping)
        }
        if case .saved = model.classifierRuleEditor.saveState {
            Label("Classifier rule saved", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .accessibilityIdentifier("S2-19-save-success")
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.classifierRuleEditor.rules.isEmpty, model.classifierRuleEditor.draft == nil {
            ContentUnavailableView("No custom classifier rules yet", systemImage: "tray")
        } else {
            HStack(alignment: .top, spacing: 16) {
                ClassifierRuleListView(model: model)
                ClassifierRuleDetailView(model: model)
            }
        }
    }

    private func classifierRuleEditorError(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(mapping.userMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(mapping.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("S2-19-error")
    }
}

private struct ClassifierRuleListView: View {
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
                .accessibilityIdentifier("S2-19-rule-row-\(rule.slug)")
            }
        }
        .frame(width: 210, alignment: .topLeading)
    }

    private func ruleLabel(_ rule: ClassifierRuleRecordSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(rule.displayName.isEmpty ? rule.slug : rule.displayName)
                .font(.callout.weight(.semibold))
            Text(rule.slug)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func ruleStatus(_ rule: ClassifierRuleRecordSnapshot) -> some View {
        if rule.isDefault {
            Text("default").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        if model.classifierRuleEditor.selectedRuleID == rule.ruleID,
           model.classifierRuleEditor.hasDirtyDraft {
            Text("dirty").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
        }
    }

    private func ruleListBackground(_ rule: ClassifierRuleRecordSnapshot) -> Color {
        if model.classifierRuleEditor.selectedRuleID == rule.ruleID {
            return Color.accentColor.opacity(0.12)
        }
        return Color.secondary.opacity(0.06)
    }
}

private struct ClassifierRuleDetailView: View {
    @ObservedObject var model: ClassifierSettingsModel

    var body: some View {
        if let draft = model.classifierRuleEditor.draft {
            VStack(alignment: .leading, spacing: 12) {
                fields(draft)
                chips(title: "Extensions", values: draft.extensions, isExtension: true)
                chips(title: "Keywords", values: draft.keywords, isExtension: false)
                riskConfirmation
                validation(draft)
                actions
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Text("Select a category or create a new category.")
                .foregroundStyle(.secondary)
        }
    }

    private func fields(_ draft: ClassifierRuleEditorDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("slug", text: draftBinding(\.slug))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("S2-19-slug")
            TextField("display name", text: draftBinding(\.displayName))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("S2-19-display-name")
            TextField("description", text: draftBinding(\.description))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("S2-19-description")
            Stepper(value: priorityBinding, in: ClassifierRuleEditorValidation.priorityRange) {
                Text("Priority \(draft.priority)")
            }
            TextField("naming template", text: draftBinding(\.namingTemplate))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("S2-19-naming-template")
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
                Button(isExtension ? "Add extension" : "Add keyword") {
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
            .accessibilityIdentifier("S2-19-remove-\(isExtension ? "extension" : "keyword")-\(value)")
        }
    }

    @ViewBuilder
    private func validation(_ draft: ClassifierRuleEditorDraft) -> some View {
        if !draft.previewConfirmed {
            Label("Impact summary required before Save; existing files are not moved or deleted.", systemImage: "eye")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("S2-19-impact-required")
        }
        ForEach(draft.validationErrors, id: \.self) { error in
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Preview impact") { model.requestClassifierRuleImpactSummary() }
                .disabled(model.classifierRuleEditor.isBusy)
                .accessibilityIdentifier("S2-19-preview-impact")
            Button("Validate") { model.validateClassifierRuleDraft() }
                .disabled(model.classifierRuleEditor.isBusy)
                .accessibilityIdentifier("S2-19-validate")
            Button("Save") { Task { await model.saveClassifierRuleDraft() } }
                .disabled(!model.classifierRuleEditor.canSave)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("S2-19-save")
            Button("Revert") { model.revertClassifierRuleDraft() }
                .disabled(!model.classifierRuleEditor.canRevert)
                .accessibilityIdentifier("S2-19-revert")
            Button("Delete category...") { model.requestDeleteSelectedClassifierRule() }
                .disabled(!model.classifierRuleEditor.canDeleteSelectedRule)
                .accessibilityIdentifier("S2-19-delete-category")
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
        riskPanel(identifier: "S2-19-matcher-impact-summary") {
            Label("Impact summary", systemImage: "eye")
                .font(.callout.weight(.semibold))
            Text(matcherImpactCopy(removal))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.cancelClassifierRuleRiskConfirmation() }
                Button("Confirm removal") { model.confirmClassifierRuleImpactSummary() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("S2-19-confirm-matcher-removal")
            }
        }
    }

    private func categoryDeleteConfirmation(_ deletion: ClassifierRuleDeleteConfirmation) -> some View {
        riskPanel(identifier: "S2-19-delete-category-confirmation") {
            Label("Delete category?", systemImage: "exclamationmark.triangle")
                .font(.callout.weight(.semibold))
            Text("This removes the category from classifier.yaml. Existing files are not moved or deleted.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(categoryDeleteDetail(deletion))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.cancelClassifierRuleRiskConfirmation() }
                Button("Confirm delete") { Task { await model.confirmDeleteSelectedClassifierRule() } }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("S2-19-confirm-delete-category")
            }
        }
    }

    private var draftImpactSummary: some View {
        riskPanel(identifier: "S2-19-impact-summary") {
            Label("Impact summary", systemImage: "eye")
                .font(.callout.weight(.semibold))
            Text("Saving this classifier draft updates future classification rules only.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Existing files are not moved, deleted, renamed, or reclassified from this page.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { model.cancelClassifierRuleRiskConfirmation() }
                Button("Confirm summary") { model.confirmClassifierRuleImpactSummary() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("S2-19-confirm-impact-summary")
            }
        }
    }

    private func riskPanel(
        identifier: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
        "Removing \(removal.kind.rawValue) '\(removal.value)' from \(removal.categoryName) " +
            "only changes the draft classifier rule. Existing files are not moved or deleted."
    }

    func categoryDeleteDetail(_ deletion: ClassifierRuleDeleteConfirmation) -> String {
        "Category: \(deletion.categoryName). Replacement category for future metadata fallback: " +
            "\(deletion.replacementCategory ?? "none")."
    }
}

private struct FlowLikeChipStack<Content: View>: View {
    let values: [String]
    let content: (String) -> Content

    var body: some View {
        if values.isEmpty {
            Text("No custom classifier rules yet")
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
