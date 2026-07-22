import SwiftUI

struct PlatformDifferencesCapabilityRow: View {
    let row: PlatformDifferencesCapabilityDisplayRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(row.name)
                    .font(.callout)
                Spacer()
                TintedCapsuleBadge(title: row.support.status.displayName, tint: statusTint)
            }
            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.format(
                "settings.platformDifferences.uiEnabled",
                L10n.string(row.support.uiEnabled ? "Yes" : "No")
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            if row.support.requiresPermission {
                Text("Requires platform permission before use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let reason = row.support.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let alternative = row.alternative, !alternative.isEmpty {
                Text(alternative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var statusTint: Color {
        switch row.support.status {
        case .available:
            .green
        case .limited:
            .orange
        case .notAvailable:
            .red
        case .unknown:
            .gray
        }
    }
}

struct PlatformDifferencesKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        SettingsKeyValueRow(label: label, value: value, labelWidth: 130, spacing: 12, valueLayout: .plain)
    }
}

struct PlatformDifferencesStatusRow: View, Identifiable {
    let title: String
    let detail: String
    let status: BindingSupportStatusSnapshot
    let reason: String?

    var id: String {
        "\(title)-\(detail)-\(status.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.callout)
                    .textSelection(.enabled)
                Spacer()
                TintedCapsuleBadge(title: status.displayName, tint: statusTint)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var statusTint: Color {
        switch status {
        case .supported:
            .green
        case .limited:
            .orange
        case .missing:
            .red
        }
    }
}

struct PlatformDifferencesCapabilityErrorBanner: View {
    let error: PlatformDifferencesCapabilityError

    var body: some View {
        SettingsStatusBanner(title: error.message, systemImage: "exclamationmark.triangle", tint: .orange) {
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }
}

struct PlatformDifferencesErrorBanner: View {
    let error: PlatformDifferencesContractError

    var body: some View {
        SettingsStatusBanner(title: error.message, systemImage: "exclamationmark.triangle", tint: .red) {
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }
}
