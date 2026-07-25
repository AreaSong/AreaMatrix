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
        TintedStatusBanner(tint: tint, contentPadding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: iconName)
                    .font(.headline)
                    .foregroundStyle(tint)
                statusContent
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("startup-recovery-startup-recovery-core-startup-recovery")
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state {
        case .checking:
            Text(L10n.string("AreaMatrix is checking startup recovery before opening the repository."))
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .completed(report):
            if let report, report.hasVisibleDetails {
                recoveryReportContent(report)
            } else {
                Text(L10n.string("Startup recovery check completed."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case let .failed(mapping):
            ErrorRecoveryMappedErrorView(
                mapping: mapping,
                retryButtonTitle: retryButtonTitle,
                isRetrying: isRetrying,
                retryAccessibilityIdentifier: "startup-recovery-startup-recovery-core-retry-startup-recovery",
                onRetry: onRetry
            )
        }
    }

    private func recoveryReportContent(_ report: RecoveryReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.format("onboarding.recovery.completedSummary", report.startupRecoverySummaryText))
                .font(.callout)
                .accessibilityIdentifier("startup-recovery-startup-recovery-core-recovery-report")
            if !report.warnings.isEmpty {
                Text(L10n.plural("startupRecovery.warningCount", count: report.warnings.count))
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
        isRetrying ? L10n.string("Retrying...") : L10n.string("Retry startup recovery")
    }

    var retryButtonIsDisabled: Bool {
        isRetrying
    }

    private var title: String {
        switch state {
        case .checking:
            L10n.string("Startup recovery")
        case .completed:
            L10n.string("Startup recovery complete")
        case .failed:
            L10n.string("Startup recovery failed")
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
        .accessibilityIdentifier("startup-recovery-error-mapping-error-mapping")
    }

    private var mappingHeader: some View {
        HStack(spacing: 8) {
            Label(mapping.kind.displayName, systemImage: iconName)
                .foregroundStyle(tint)
            Text(L10n.format("onboarding.recovery.severity", mapping.severity.displayName))
                .foregroundStyle(.secondary)
            Text(L10n.format("onboarding.recovery.recoverability", mapping.recoverability.displayName))
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var technicalDetails: some View {
        DisclosureGroup(L10n.string("Technical Details")) {
            Text(rawContextText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private var mappedActionText: String {
        mapping
            .recoveryText(fallback: L10n.string("Retry the failed action or collect diagnostics from the source page."))
    }

    private var rawContextText: String {
        mapping.rawContext.isEmpty ? L10n.string("onboarding.recovery.no-technical-context") : mapping.rawContext
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
