import SwiftUI

struct RepoPlatformCapabilitySection: View {
    let state: RepositorySettingsCapabilityState
    let onOpenPlatformCapabilities: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Platform capabilities")
                .font(.headline)
            content
            Button(action: onOpenPlatformCapabilities) {
                Label("Platform capabilities", systemImage: "rectangle.3.group")
            }
            .accessibilityIdentifier("S4-X-08-C4-17-open-platform-capabilities")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading platform capabilities...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case let .loaded(capabilities):
            capabilityRows(capabilities.repositorySettingsRows)
        case let .failed(capabilities, error):
            capabilityRows(capabilities.repositorySettingsRows)
            RepositorySettingsCapabilityErrorBanner(error: error)
        }
    }

    private func capabilityRows(_ rows: [RepositorySettingsCapabilityRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                RepositorySettingsCapabilityRowView(row: row)
            }
        }
    }
}

private struct RepositorySettingsCapabilityRowView: View {
    let row: RepositorySettingsCapabilityRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: row.support.status.systemImage)
                .foregroundStyle(row.support.status.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.callout.weight(.medium))
                    Text(row.support.status.rawValue)
                        .font(.caption)
                        .foregroundStyle(row.support.status.tint)
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String? {
        if let reason = row.support.reason, !reason.isEmpty {
            return reason
        }
        if row.support.uiEnabled {
            return row.support.requiresPermission ? "Requires platform permission." : nil
        }
        return row.unavailableEffect
    }
}

private struct RepositorySettingsCapabilityErrorBanner: View {
    let error: RepositorySettingsCapabilityError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private extension PlatformCapabilityStatusSnapshot {
    var systemImage: String {
        switch self {
        case .available:
            "checkmark.circle"
        case .limited:
            "exclamationmark.circle"
        case .notAvailable:
            "xmark.circle"
        case .unknown:
            "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .available:
            .green
        case .limited:
            .orange
        case .notAvailable, .unknown:
            .secondary
        }
    }
}
