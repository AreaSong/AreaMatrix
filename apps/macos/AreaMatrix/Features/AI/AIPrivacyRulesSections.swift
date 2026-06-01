import SwiftUI

extension AIPrivacyRulesView {
    var fieldSection: some View {
        AdvancedSettingsSection(title: "Remote allowed fields") {
            if !privacyModel.canEditRemoteFields {
                Text("Remote AI is blocked.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(privacyModel.fields, id: \.field, content: fieldRow)
        }
    }

    func fieldRow(_ field: AiPrivacyFieldState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: fieldBinding(field)) {
                Text(aiPrivacyInputFieldLabel(field.field))
            }
            .disabled(!privacyModel.canEditRemoteFields)
            Text("\(field.allowRemote ? "Allowed" : "Blocked") - \(field.lastMatchedCount) recent matches")
                .font(.caption)
                .foregroundStyle(field.allowRemote ? Color.secondary : Color.orange)
            if field.field == .noteSummary {
                Text("Derived from your note. Full note text is never sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .id(AIPrivacyRulesRouteFocus.field(field.field).targetID)
        .aiPrivacyRulesFocusHighlight(isFocused(field: field.field))
    }

    var ruleListSection: some View {
        AdvancedSettingsSection(title: "Privacy rules") {
            if privacyModel.rules.isEmpty {
                AIPrivacyEmptyRulesView(
                    onAddRule: beginAddRule,
                    onTemplates: openTemplates
                )
            } else {
                HStack(spacing: 10) {
                    Button("Add rule", action: beginAddRule)
                    Button("Use recommended templates...", action: openTemplates)
                }
                ForEach(privacyModel.rules, id: \.ruleId, content: ruleRow)
            }
        }
    }

    func ruleRow(_ rule: AiPrivacyRuleRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(rule.enabled ? "Enabled" : "Disabled").frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(rule.kind.s309Label): \(rule.pattern)")
                    .font(.callout.weight(.medium))
                Text("\(rule.appliesTo.s309Label), \(rule.matchCount) files, \(rule.s309LastMatchedText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let description = rule.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Edit") { beginEditRule(rule) }
            Button(rule.enabled ? "Disable" : "Enable") { toggleRule(rule) }
            Button("Delete...") { deletionCandidate = rule }
        }
        .font(.callout)
        .id(AIPrivacyRulesRouteFocus.rule(ruleID: rule.ruleId).targetID)
        .aiPrivacyRulesFocusHighlight(isFocused(ruleID: rule.ruleId))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rule.s309AccessibilityLabel)
    }

    @ViewBuilder
    var ruleEditorSection: some View {
        if editorMode == .visible {
            AIPrivacyRuleEditorView(
                title: editorDraft.isEditing ? "Edit rule" : "Add rule",
                draft: $editorDraft,
                registry: registry,
                isSaving: privacyModel.isSaving,
                onSave: saveDraftRule,
                onCancel: cancelEditor
            )
        }
    }

    var testRulesSection: some View {
        AdvancedSettingsSection(title: "Test rules") {
            TextField("Test repo-relative path", text: testPath)
                .textFieldStyle(.roundedBorder)
            TextField("Current category", text: testCategoryBinding)
                .textFieldStyle(.roundedBorder)
            TextField("Current tags, comma separated", text: testTagsBinding)
                .textFieldStyle(.roundedBorder)
            Button("Test rules", action: testRules)
                .disabled(privacyModel.isEvaluating || testFileContext.isEmpty)
                .accessibilityIdentifier("S3-09-C3-09-test-rules")
            if !privacyModel.featureEvaluations.isEmpty {
                AIPrivacyRuleTestResultView(evaluations: privacyModel.featureEvaluations)
            }
        }
    }
}
