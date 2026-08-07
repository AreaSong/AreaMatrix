import SwiftUI

struct AISettingsLoadingView: View {
    var body: some View {
        AdvancedSettingsSection(title: L10n.string("AI features")) {
            ProgressView("Loading AI settings...")
            Text(L10n.string("AI controls are disabled until settings finish loading."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct AISettingsLoadFailureView: View {
    let error: AISettingsError
    let retry: () -> Void
    let openLog: () -> Void

    var body: some View {
        AISettingsInlineBanner(error: error, tint: .red) {
            Button(L10n.string("Retry"), action: retry)
            Button(L10n.string("View AI call log"), action: openLog)
        }
    }
}

struct AISettingsFeatureRow: View {
    let row: AISettingsFeatureRowSnapshot
    var isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Toggle(row.feature.title, isOn: isOn)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                Text(row.feature.title)
                    .font(.callout.weight(.medium))
                Text("\(row.providerLabel) - \(row.remoteScope)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let reason = row.disabledReason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        [
            row.feature.title,
            row.enabled ? L10n.string("On") : L10n.string("Off"),
            row.providerLabel,
            row.remoteScope,
            row.disabledReason ?? ""
        ].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
