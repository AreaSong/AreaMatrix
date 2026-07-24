import SwiftUI

extension AIPrivacyRulesView {
    var fieldSection: some View {
        AdvancedSettingsSection(title: L10n.string("Remote allowed fields")) {
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
            Text(L10n.format(
                "ai.privacy.fieldMatchSummary",
                field.allowRemote ? L10n.string("Allowed") : L10n.string("Blocked"),
                field.lastMatchedCount
            ))
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
        AdvancedSettingsSection(title: L10n.string("Privacy rules")) {
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
            Text(rule.enabled ? L10n.string("Enabled") : L10n.string("Disabled"))
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(rule.kind.aiPrivacyRulesLabel): \(rule.pattern)")
                    .font(.callout.weight(.medium))
                Text(L10n.format(
                    "ai.privacy.ruleSummary",
                    rule.appliesTo.aiPrivacyRulesLabel,
                    rule.matchCount,
                    rule.aiPrivacyRulesLastMatchedText
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                if let description = rule.description, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Edit") { beginEditRule(rule) }
            Button(rule.enabled ? L10n.string("Disable") : L10n.string("Enable")) { toggleRule(rule) }
            Button("Delete...") { deletionCandidate = rule }
        }
        .font(.callout)
        .id(AIPrivacyRulesRouteFocus.rule(ruleID: rule.ruleId).targetID)
        .aiPrivacyRulesFocusHighlight(isFocused(ruleID: rule.ruleId))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rule.aiPrivacyRulesAccessibilityLabel)
    }

    @ViewBuilder
    var ruleEditorSection: some View {
        if editorMode == .visible {
            AIPrivacyRuleEditorView(
                title: editorDraft.isEditing ? L10n.string("Edit rule") : L10n.string("Add rule"),
                draft: $editorDraft,
                registry: registry,
                isSaving: privacyModel.isSaving,
                onSave: saveDraftRule,
                onCancel: cancelEditor
            )
        }
    }

    var testRulesSection: some View {
        AdvancedSettingsSection(title: L10n.string("Test rules")) {
            TextField("Test repo-relative path", text: testPath)
                .textFieldStyle(.roundedBorder)
            TextField("Current category", text: testCategoryBinding)
                .textFieldStyle(.roundedBorder)
            TextField("Current tags, comma separated", text: testTagsBinding)
                .textFieldStyle(.roundedBorder)
            Button("Test rules", action: testRules)
                .disabled(privacyModel.isEvaluating || testFileContext.isEmpty)
                .accessibilityIdentifier("ai-privacy-rules-ai-privacy-rules-core-test-rules")
            if !privacyModel.featureEvaluations.isEmpty {
                AIPrivacyRuleTestResultView(evaluations: privacyModel.featureEvaluations)
            }
        }
    }
}
