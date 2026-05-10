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
        case let .completed(report):
            if let report, report.hasVisibleDetails {
                recoveryReportContent(report)
            } else {
                Text("Startup recovery check completed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case let .failed(mapping):
            ErrorRecoveryMappedErrorView(
                mapping: mapping,
                retryButtonTitle: retryButtonTitle,
                isRetrying: isRetrying,
                retryAccessibilityIdentifier: "S1-32-C1-16-retry-startup-recovery",
                onRetry: onRetry
            )
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
            "Startup recovery"
        case .completed:
            "Startup recovery complete"
        case .failed:
            "Startup recovery failed"
        }
    }

    private var iconName: String {
        switch state {
        case .checking:
            "arrow.clockwise.circle"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch state {
        case .failed:
            .red
        default:
            .primary
        }
    }
}

struct ErrorRecoveryMappedErrorView: View {
    let mapping: CoreErrorMappingSnapshot
    let retryButtonTitle: String
    let isRetrying: Bool
    let retryAccessibilityIdentifier: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mappingHeader
            Text(mapping.userMessage)
            Text(mappedActionText)
                .font(.callout)
                .foregroundStyle(.secondary)
            technicalDetails
            Button(retryButtonTitle, action: onRetry)
                .disabled(isRetrying)
                .accessibilityIdentifier(retryAccessibilityIdentifier)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S1-32-C1-21-error-mapping")
    }

    private var mappingHeader: some View {
        HStack(spacing: 8) {
            Label(mapping.kind.rawValue, systemImage: iconName)
                .foregroundStyle(tint)
            Text("Severity: \(mapping.severity.rawValue)")
                .foregroundStyle(.secondary)
            Text("Recoverability: \(mapping.recoverability.rawValue)")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var technicalDetails: some View {
        DisclosureGroup("Technical Details") {
            Text(rawContextText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private var mappedActionText: String {
        mapping.suggestedAction.isEmpty ? "Retry the failed action or collect diagnostics from the source page." :
            mapping.suggestedAction
    }

    private var rawContextText: String {
        mapping.rawContext.isEmpty ? "No technical context was provided by Core." : mapping.rawContext
    }

    private var iconName: String {
        switch mapping.severity {
        case .low:
            "info.circle"
        case .medium:
            "exclamationmark.circle"
        case .high:
            "exclamationmark.triangle"
        case .critical:
            "xmark.octagon"
        }
    }

    private var tint: Color {
        switch mapping.severity {
        case .low:
            .blue
        case .medium:
            .orange
        case .high, .critical:
            .red
        }
    }
}
