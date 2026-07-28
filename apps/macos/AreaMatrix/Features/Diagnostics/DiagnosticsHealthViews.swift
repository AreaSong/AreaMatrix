import SwiftUI

struct DiagnosticsHealthSection: View {
    let health: AppObservabilityHealth

    var body: some View {
        SettingsFormSection(title: L10n.string("observability.health.title")) {
            summaryRows
            dropBreakdown
            degradedState
            issueBreakdown
        }
    }

    @ViewBuilder
    private var summaryRows: some View {
        LabeledContent(
            L10n.string("observability.health.initialized"),
            value: booleanValue(health.initialized)
        )
        LabeledContent(L10n.string("observability.health.mode"), value: health.mode.localizedLabel)
        LabeledContent(
            L10n.string("observability.health.memory"),
            value: "\(health.memoryEventCount) / \(health.memoryCapacity)"
        )
        LabeledContent(
            L10n.string("observability.health.disk"),
            value: "\(bytes(health.fileUsageBytes)) / \(bytes(health.diskBudgetBytes))"
        )
        LabeledContent(
            L10n.string("observability.health.oldestEvent"),
            value: timestamp(health.oldestEventTimestampMilliseconds)
        )
        LabeledContent(
            L10n.string("observability.health.lastRotation"),
            value: timestamp(health.lastRotationAtMilliseconds)
        )
        LabeledContent(
            L10n.string("observability.health.queue"),
            value: "\(health.coreQueueDepth) / \(health.coreQueueCapacity)"
        )
        LabeledContent(
            L10n.string("observability.health.writer"),
            value: booleanValue(health.writerAvailable)
        )
        LabeledContent(
            L10n.string("observability.health.callback"),
            value: booleanValue(health.coreCallbackConnected)
        )
        LabeledContent(L10n.string("observability.health.incidents"), value: "\(health.incidentCount)")
        LabeledContent(
            L10n.string("observability.health.activeIncident"),
            value: health.activeIncidentID ?? L10n.string("observability.health.none")
        )
    }

    private var dropBreakdown: some View {
        DisclosureGroup(L10n.string("observability.health.eventLoss")) {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(L10n.string("observability.health.dropped"), value: "\(health.droppedEvents)")
                LabeledContent(AppObservabilitySeverity.trace.localizedLabel, value: "\(health.droppedTraceEvents)")
                LabeledContent(AppObservabilitySeverity.debug.localizedLabel, value: "\(health.droppedDebugEvents)")
                LabeledContent(AppObservabilitySeverity.info.localizedLabel, value: "\(health.droppedInfoEvents)")
                LabeledContent(AppObservabilitySeverity.warn.localizedLabel, value: "\(health.droppedWarnEvents)")
                LabeledContent(AppObservabilitySeverity.error.localizedLabel, value: "\(health.droppedErrorEvents)")
                LabeledContent(
                    L10n.string("observability.health.ingressDropped"),
                    value: "\(health.ingressDroppedEvents)"
                )
                LabeledContent(
                    L10n.string("observability.health.redactionRejected"),
                    value: "\(health.coreRedactionRejectedEvents)"
                )
                LabeledContent(L10n.string("observability.health.rejected"), value: "\(health.rejectedEvents)")
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var degradedState: some View {
        if let reason = health.degradedReason {
            LabeledContent(L10n.string("observability.health.degradedReason")) {
                Text(diagnosticsTechnicalText(reason))
                    .font(.caption.monospaced())
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var issueBreakdown: some View {
        if !health.issues.isEmpty {
            DisclosureGroup(L10n.format("observability.health.issues.format", health.issues.count)) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(health.issues) { issue in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diagnosticsTechnicalText(issue.code, reason: .technicalIdentifier))
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                Text(issue.source.localizedLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func booleanValue(_ value: Bool) -> String {
        if value { return L10n.string("settings.value.yes") }
        return L10n.string("settings.value.no")
    }

    private func timestamp(_ milliseconds: Int64?) -> String {
        guard let milliseconds else { return L10n.string("observability.health.none") }
        return Self.dateFormatter.string(from: Date(timeIntervalSince1970: Double(milliseconds) / 1000))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
