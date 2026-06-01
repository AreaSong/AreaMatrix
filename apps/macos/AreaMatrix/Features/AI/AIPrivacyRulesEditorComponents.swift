import SwiftUI

struct AIPrivacyEmptyRulesView: View {
    let onAddRule: () -> Void
    let onTemplates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No AI privacy rules yet")
                .font(.headline)
            Text(
                "Remote AI is still off by default. Add rules to block specific folders, keywords, " +
                    "extensions, categories, or tags whenever AI is enabled."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Add rule", action: onAddRule)
                Button("Use recommended templates...", action: onTemplates)
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
            Picker("Type", selection: $draft.kind) {
                ForEach(AiPrivacyRuleKind.s309Cases, id: \.self) { Text($0.s309Label).tag($0) }
            }
            .pickerStyle(.segmented)
            TextField("Pattern", text: $draft.pattern)
                .textFieldStyle(.roundedBorder)
            Picker("Applies to", selection: $draft.appliesTo) {
                Text("Remote AI").tag(AiPrivacyRuleAppliesTo.remoteAi)
                Text("Local and remote AI").tag(AiPrivacyRuleAppliesTo.localAndRemoteAi)
            }
            .pickerStyle(.segmented)
            TextField("Description", text: $draft.description)
                .textFieldStyle(.roundedBorder)
            Toggle("Enabled", isOn: $draft.enabled)
            HStack(spacing: 10) {
                Button("Save rule", action: onSave)
                    .disabled(!draft.canSave(registry: registry) || isSaving)
                    .accessibilityIdentifier("S3-09-C3-09-save-rule")
                Button("Cancel", action: onCancel)
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
            Text("Use recommended templates...")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(
                "Templates never auto-create rules. Select the ones you want and add them explicitly."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            ForEach(AIPrivacyRuleTemplate.allCases) { template in
                Toggle(template.title, isOn: binding(for: template))
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Add selected rules", action: onAdd)
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
                Text("\(evaluation.feature.s309Label): \(report.decision.s309Label)")
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
                    Text("Skipped reason: \(skippedReason.s309Label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func providerGateText(_ report: AiPrivacyEvaluationReport) -> String {
        report.providerGateReason?.s309Label ?? "none"
    }
}
