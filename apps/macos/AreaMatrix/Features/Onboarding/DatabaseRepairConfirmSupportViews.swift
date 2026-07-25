import SwiftUI

struct StartupRecoveryCheckStatusView: View {
    let state: DatabaseStartupRecoveryState
    let onRetry: () -> Void

    var body: some View {
        switch state {
        case .idle, .checking:
            Label(L10n.string("Checking startup recovery state..."), systemImage: "arrow.clockwise.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("database-repair-startup-recovery-core-startup-recovery-checking")
        case let .completed(report):
            completedContent(report)
                .accessibilityIdentifier("database-repair-startup-recovery-core-startup-recovery-completed")
        case let .failed(mapping):
            failedContent(mapping)
                .accessibilityIdentifier("database-repair-startup-recovery-core-startup-recovery-failed")
        }
    }

    private func completedContent(_ report: RecoveryReportSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.string("Startup recovery checked"), systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(.green)
            if let report {
                Text(report.startupRecoverySummaryText)
                    .font(.callout)
                ForEach(report.warnings.prefix(3), id: \.self) { warning in
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } else {
                Text(L10n.string("No leftover staging files or staging DB rows required recovery."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failedContent(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("Startup recovery failed"), systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.red)
            Text(mapping.userMessage)
                .font(.callout)
            Text(mapping.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            DisclosureGroup(L10n.string("Technical Details")) {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.callout)
            Button(L10n.string("Retry startup recovery"), action: onRetry)
                .accessibilityIdentifier("database-repair-startup-recovery-core-retry-startup-recovery")
        }
    }
}

struct RepairChecklistSection: View {
    let title: String
    let systemImage: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RepairProgressView: View {
    let currentStep: DatabaseRepairProgressStep

    var body: some View {
        TintedStatusBanner(tint: .blue, fillsWidth: false) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.string("Repair in progress"), systemImage: "arrow.clockwise.circle")
                    .font(.headline)
                ForEach(DatabaseRepairProgressStep.allCases, id: \.self) { step in
                    HStack(spacing: 8) {
                        if step == currentStep {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                        Text(step.displayName)
                            .font(.callout)
                            .foregroundStyle(step == currentStep ? .primary : .secondary)
                    }
                }
            }
        }
    }
}
