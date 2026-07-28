import SwiftUI

struct DiagnosticsActivityList: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let events: [DiagnosticsProjectedEvent]

    var body: some View {
        if events.isEmpty {
            DiagnosticsConsoleEmptyView()
        } else {
            List(events.reversed()) { projected in
                DisclosureGroup {
                    technicalDetails(projected.event)
                        .padding(.leading, 30)
                        .padding(.vertical, 6)
                } label: {
                    activityHeader(projected)
                }
            }
        }
    }

    private func activityHeader(_ projected: DiagnosticsProjectedEvent) -> some View {
        let event = projected.event
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.severity.symbolName)
                .foregroundStyle(event.severity.tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(localizer.resolve(DiagnosticsCatalogPresentation.title(for: projected.actionGroup)))
                    .font(.body.weight(.medium))
                Text(localizer.resolve(DiagnosticsEventPresentation.outcome(event.outcome)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let code = event.error?.code {
                    Text(localizer.resolve(L10n.verbatim(code, reason: .technicalIdentifier)))
                        .font(.caption.monospaced())
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            incidentFlag(event)
            Text(event.diagnosticsDate, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func incidentFlag(_ event: ObservabilityEventSnapshot) -> some View {
        if event.incidentID != nil {
            Image(systemName: "flag.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel(L10n.string("observability.incident.flagged"))
        }
    }

    private func technicalDetails(_ event: ObservabilityEventSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            DiagnosticsTechnicalRow(label: L10n.string("observability.field.action"), value: event.actionID)
            DiagnosticsTechnicalRow(label: L10n.string("observability.field.component"), value: event.componentID)
            DiagnosticsTechnicalRow(label: L10n.string("observability.field.trace"), value: event.traceID)
            DiagnosticsTechnicalRow(label: L10n.string("observability.field.phase"), value: event.phase)
            if let duration = event.durationMilliseconds {
                DiagnosticsTechnicalRow(
                    label: L10n.string("observability.field.duration"),
                    value: L10n.format("observability.duration.format", duration)
                )
            }
        }
    }
}

struct DiagnosticsTimelineView: View {
    let events: [DiagnosticsProjectedEvent]

    var body: some View {
        if events.isEmpty {
            DiagnosticsConsoleEmptyView()
        } else {
            List(events) { projected in
                let event = projected.event
                HStack(alignment: .top, spacing: 12) {
                    Text(relativeTime(event))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 90, alignment: .trailing)
                    Image(systemName: event.severity.symbolName)
                        .foregroundStyle(event.severity.tint)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnosticsTechnicalText(event.actionID, reason: .technicalIdentifier))
                            .font(.callout.monospaced())
                        Text(diagnosticsTechnicalText(
                            "\(event.componentID) · \(event.phase) · \(event.outcome)"
                        ))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    duration(event)
                }
                .padding(.vertical, 3)
                .textSelection(.enabled)
            }
        }
    }

    private func relativeTime(_ event: ObservabilityEventSnapshot) -> String {
        let origin = events.first?.event.monotonicTimestampNanoseconds ?? 0
        let delta = event.monotonicTimestampNanoseconds >= origin
            ? event.monotonicTimestampNanoseconds - origin : 0
        return String(format: "+%.3f ms", Double(delta) / 1_000_000)
    }

    @ViewBuilder
    private func duration(_ event: ObservabilityEventSnapshot) -> some View {
        if let duration = event.durationMilliseconds {
            Text(L10n.format("observability.duration.format", duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct DiagnosticsTraceTreeView: View {
    let rows: [DiagnosticsSpanRow]

    var body: some View {
        if rows.isEmpty {
            DiagnosticsConsoleEmptyView()
        } else {
            List(rows) { row in
                HStack(spacing: 8) {
                    Color.clear.frame(width: CGFloat(row.depth) * 18)
                    Image(systemName: row.isDetachedRoot ? "link.badge.plus" : treeSymbol(row))
                        .foregroundStyle(row.isDetachedRoot ? .orange : .secondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnosticsTechnicalText(row.event.componentID, reason: .technicalIdentifier))
                            .font(.callout.monospaced())
                        Text(diagnosticsTechnicalText(
                            "\(row.event.actionID) · \(row.event.phase) · \(row.event.outcome)"
                        ))
                        .font(.caption.monospaced())
                        .foregroundStyle(row.event.severity.tint)
                    }
                    Spacer()
                    if let duration = row.event.durationMilliseconds {
                        Text(L10n.format("observability.duration.format", duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func treeSymbol(_ row: DiagnosticsSpanRow) -> String {
        row.depth == 0 ? "circle" : "arrow.turn.down.right"
    }
}

struct DiagnosticsCausalGraphView: View {
    let projection: DiagnosticsCausalProjection
    @State private var selectedNodeID: String?

    var body: some View {
        if projection.nodes.isEmpty {
            DiagnosticsConsoleEmptyView()
        } else {
            HSplitView {
                nodesColumn
                relationshipsColumn
            }
        }
    }

    private var nodesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("observability.causal.nodes")).font(.headline).padding()
            Divider()
            List(projection.nodes, selection: $selectedNodeID) { node in
                VStack(alignment: .leading, spacing: 3) {
                    Text(diagnosticsTechnicalText(node.technicalID, reason: .technicalIdentifier))
                        .font(.callout.monospaced())
                    Text(diagnosticsTechnicalText("\(node.componentID) · \(node.actionID)"))
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .tag(Optional(node.id))
                .textSelection(.enabled)
            }
        }
        .frame(minWidth: 360)
    }

    private var relationshipsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.string("observability.causal.relationships")).font(.headline).padding()
            Divider()
            List(visibleEdges) { edge in
                HStack(spacing: 10) {
                    Image(systemName: edge.kind == .parentSpan ? "arrow.down.right" : "arrow.clockwise")
                        .foregroundStyle(edge.kind == .parentSpan ? .blue : .orange)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(edge.kind.label).font(.caption.weight(.semibold))
                        Text(diagnosticsTechnicalText("\(edge.sourceID) -> \(edge.destinationID)"))
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }
        }
        .frame(minWidth: 420)
    }

    private var visibleEdges: [DiagnosticsCausalEdge] {
        guard let selectedNodeID,
              let node = projection.nodes.first(where: { $0.id == selectedNodeID }) else {
            return projection.edges
        }
        return projection.edges.filter { $0.sourceID == node.technicalID || $0.destinationID == node.technicalID }
    }
}

struct DiagnosticsTerminalView: View {
    let events: [DiagnosticsProjectedEvent]

    var body: some View {
        diagnosticsTextStream(events.map(\.terminalLine), empty: events.isEmpty)
    }
}

struct DiagnosticsRawEventsView: View {
    let events: [DiagnosticsProjectedEvent]

    var body: some View {
        diagnosticsTextStream(events.map(\.rawJSON), empty: events.isEmpty)
    }
}

@ViewBuilder
private func diagnosticsTextStream(_ lines: [String], empty: Bool) -> some View {
    if empty {
        DiagnosticsConsoleEmptyView()
    } else {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { line in
                    Text(diagnosticsTechnicalText(line.element))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct DiagnosticsConsoleEmptyView: View {
    var body: some View {
        ContentUnavailableView(
            L10n.string("observability.console.empty"),
            systemImage: "waveform.path.ecg"
        )
    }
}

struct DiagnosticsTechnicalRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(diagnosticsTechnicalText(value))
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

private extension ObservabilityEventSnapshot {
    var diagnosticsDate: Date {
        Date(timeIntervalSince1970: Double(wallTimestampMilliseconds) / 1000)
    }
}

private extension DiagnosticsCausalEdge.Kind {
    var label: String {
        switch self {
        case .parentSpan: L10n.string("observability.causal.parentSpan")
        case .retry: L10n.string("observability.causal.retry")
        }
    }
}

func diagnosticsTechnicalText(
    _ value: String,
    reason: VerbatimReason = .technicalDetail
) -> String {
    L10n.resolve(L10n.verbatim(value, reason: reason))
}
