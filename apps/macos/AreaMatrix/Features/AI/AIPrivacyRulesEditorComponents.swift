import SwiftUI

struct AIPrivacyEmptyRulesView: View {
    let onAddRule: () -> Void
    let onTemplates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("No AI privacy rules yet"))
                .font(.headline)
            Text(L10n.string("ai.privacy.emptyRulesDetail"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(L10n.string("Add rule"), action: onAddRule)
                Button(L10n.string("Use recommended templates..."), action: onTemplates)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AIPrivacyRuleEditorView: View {
    let title: String
    @Binding var draft: AIPrivacyRuleEditorDraft
    let registry: AIPrivacyRuleRegistrySnapshot
    let isSaving: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        AdvancedSettingsSection(title: title) {
            Picker(L10n.string("Type"), selection: $draft.kind) {
                ForEach(AIPrivacyRuleKindState.aiPrivacyRulesCases, id: \.self) { Text($0.aiPrivacyRulesLabel).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField(L10n.string("Pattern"), text: $draft.pattern)
                .textFieldStyle(.roundedBorder)
            Picker(L10n.string("Applies to"), selection: $draft.appliesTo) {
                Text(L10n.string("Remote AI")).tag(AIPrivacyRuleAppliesToState.remoteAi)
                Text(L10n.string("Local and remote AI")).tag(AIPrivacyRuleAppliesToState.localAndRemoteAi)
            }
            .pickerStyle(.segmented)
            TextField(L10n.string("Description"), text: $draft.description)
                .textFieldStyle(.roundedBorder)
            Toggle(L10n.string("Enabled"), isOn: $draft.enabled)
            HStack(spacing: 10) {
                Button(L10n.string("Save rule"), action: onSave)
                    .disabled(!draft.canSave(registry: registry) || isSaving)
                    .accessibilityIdentifier("ai-privacy-rules-ai-privacy-rules-core-save-rule")
                Button(L10n.string("Cancel"), action: onCancel)
                Text(draft.validationMessage(registry: registry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AIPrivacyRuleTemplatesSheet: View {
    @Binding var selectedTemplates: Set<AIPrivacyRuleTemplate>
    let isSaving: Bool
    let onCancel: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("Use recommended templates..."))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(
                L10n.string("Templates never auto-create rules. Select the ones you want and add them explicitly.")
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            ForEach(AIPrivacyRuleTemplate.allCases) { template in
                Toggle(template.title, isOn: binding(for: template))
            }
            HStack {
                Spacer()
                Button(L10n.string("Cancel"), action: onCancel)
                Button(L10n.string("Add selected rules"), action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTemplates.isEmpty || isSaving)
            }
        }
        .padding(24)
        .frame(width: 560)
    }

    private func binding(for template: AIPrivacyRuleTemplate) -> Binding<Bool> {
        Binding(
            get: { selectedTemplates.contains(template) },
            set: { isSelected in
                if isSelected {
                    selectedTemplates.insert(template)
                } else {
                    selectedTemplates.remove(template)
                }
            }
        )
    }
}

struct AIPrivacyRuleTestResultView: View {
    let evaluations: [AIPrivacyRuleFeatureEvaluation]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(evaluations) { evaluation in
                let report = evaluation.report
                Text("\(evaluation.feature.aiPrivacyRulesLabel): \(report.decision.aiPrivacyRulesLabel)")
                    .font(.callout.weight(.medium))
                Text(report.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Provider gate: \(providerGateText(report))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Sent fields: \(privacySentFields(report.sentFields))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Blocked fields: \(privacySentFields(report.blockedFields))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Allowed fields: \(privacySentFields(report.allowedFields))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let matchedField = report.matchedFieldType {
                    Text("Matched field: \(aiPrivacyInputFieldLabel(matchedField))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !report.matchedRules.isEmpty {
                    Text("Matched by \(report.matchedRules.map(\.name).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let skippedReason = report.skippedReason {
                    Text("Skipped reason: \(skippedReason.aiPrivacyRulesLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func providerGateText(_ report: AIPrivacyEvaluationReportSnapshot) -> String {
        report.providerGateReason?.aiPrivacyRulesLabel ?? L10n.string("None")
    }
}
