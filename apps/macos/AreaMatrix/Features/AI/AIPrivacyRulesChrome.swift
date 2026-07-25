import SwiftUI

struct AIPrivacyRulesHeader: View {
    let repoPath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("AI Privacy Rules"))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(repoPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text(L10n.string("ai.privacy.headerDetail"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

struct AIPrivacyRulesRemoteGateSection: View {
    let remoteGateStatus: String
    let providerStatusText: String
    let verifiedStatusText: String
    let enabledStatusText: String
    let featureScopeText: String
    let allowRemoteGateDisabled: Bool
    let blockRemoteGateDisabled: Bool
    let onAllowRemoteGate: () -> Void
    let onBlockRemoteGate: () -> Void
    let onConfigureRemoteAI: () -> Void

    var body: some View {
        AdvancedSettingsSection(title: L10n.string("Remote AI privacy gate")) {
            AdvancedSettingsKeyValueRow(label: L10n.string("Status"), value: remoteGateStatus)
            AdvancedSettingsKeyValueRow(label: L10n.string("Remote provider"), value: providerStatusText)
            AdvancedSettingsKeyValueRow(label: L10n.string("Provider verified"), value: verifiedStatusText)
            AdvancedSettingsKeyValueRow(label: L10n.string("Remote provider enabled"), value: enabledStatusText)
            AdvancedSettingsKeyValueRow(label: L10n.string("Feature scope"), value: featureScopeText)
            Text(L10n.string("ai.privacy.remoteGateDetail"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(L10n.string("Allow remote AI after provider consent"), action: onAllowRemoteGate)
                    .disabled(allowRemoteGateDisabled)
                    .accessibilityIdentifier(
                        "ai-privacy-rules-ai-privacy-rules-core-allow-remote-ai-after-provider-consent"
                    )
                Button(L10n.string("Block remote AI with privacy gate"), action: onBlockRemoteGate)
                    .disabled(blockRemoteGateDisabled)
                    .accessibilityIdentifier("ai-privacy-rules-ai-privacy-rules-core-block-remote-ai-privacy-gate")
            }
            Button(L10n.string("Configure remote AI"), action: onConfigureRemoteAI)
                .accessibilityIdentifier("ai-privacy-rules-remote-provider-config-core-configure-remote-ai")
        }
    }
}

struct AIPrivacyRulesFooter: View {
    let isSaving: Bool
    let onClose: () -> Void

    var body: some View {
        HStack {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.string("Saving AI privacy rules"))
            }
            Spacer()
            Button(L10n.string("Close"), action: onClose)
        }
        .padding(16)
    }
}
