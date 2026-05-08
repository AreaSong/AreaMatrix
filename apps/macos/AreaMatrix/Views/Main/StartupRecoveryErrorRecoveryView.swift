import SwiftUI

struct StartupRecoveryErrorRecoveryView: View {
    let state: MainLoadingRecoveryState
    let isRetrying: Bool
    let onRetry: () -> Void

    init(
        state: MainLoadingRecoveryState,
        isRetrying: Bool = false,
        onRetry: @escaping () -> Void
    ) {
        self.state = state
        self.isRetrying = isRetrying
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: iconName)
                .font(.headline)
                .foregroundStyle(tint)
            statusContent
            if case .failed = state {
                Button(retryButtonTitle, action: onRetry)
                    .disabled(retryButtonIsDisabled)
                    .accessibilityIdentifier("S1-32-C1-16-retry-startup-recovery")
            }
        }
        .padding(14)
        .frame(maxWidth: 640, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S1-32-C1-16-startup-recovery")
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .checking:
            Text("AreaMatrix is checking startup recovery before opening the repository.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .completed(let report):
            if let report, report.hasVisibleDetails {
                recoveryReportContent(report)
            } else {
                Text("Startup recovery check completed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let mapping):
            Text(mapping.userMessage)
            Text(mapping.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            DisclosureGroup("Technical Details") {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.callout)
        }
    }

    private func recoveryReportContent(_ report: RecoveryReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("启动恢复已完成：\(report.startupRecoverySummaryText)")
                .font(.callout)
                .accessibilityIdentifier("S1-32-C1-16-recovery-report")
            if !report.warnings.isEmpty {
                Text("Warnings: \(report.warnings.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(report.warnings.prefix(3), id: \.self) { warning in
                    Text(warning)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    var retryButtonTitle: String {
        isRetrying ? "Retrying..." : "Retry startup recovery"
    }

    var retryButtonIsDisabled: Bool {
        isRetrying
    }

    private var title: String {
        switch state {
        case .checking:
            return "Startup recovery"
        case .completed:
            return "Startup recovery complete"
        case .failed:
            return "Startup recovery failed"
        }
    }

    private var iconName: String {
        switch state {
        case .checking:
            return "arrow.clockwise.circle"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch state {
        case .failed:
            return .red
        default:
            return .primary
        }
    }
}
