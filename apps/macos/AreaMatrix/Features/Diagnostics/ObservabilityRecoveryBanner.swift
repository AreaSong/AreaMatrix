import SwiftUI

struct ObservabilityRecoveryBanner: View {
    let incidentID: String
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("observability.recovery.title"))
                    .font(.callout.weight(.semibold))
                Text(L10n.string("observability.recovery.detail"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(L10n.string("observability.recovery.open"), action: onOpen)
                .buttonStyle(.borderedProminent)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(L10n.string("observability.recovery.dismiss"))
            .accessibilityLabel(L10n.string("observability.recovery.dismiss"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("observability-interrupted-session-\(incidentID)")
    }
}
