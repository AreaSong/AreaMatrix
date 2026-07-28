import SwiftUI

struct DiagnosticsEventInspectorView: View {
    let events: [DiagnosticsProjectedEvent]
    @Binding var selectedEventID: String?
    let isOfflinePackage: Bool

    var body: some View {
        if events.isEmpty {
            DiagnosticsConsoleEmptyView()
        } else {
            HSplitView {
                eventList
                detail
            }
        }
    }

    private var eventList: some View {
        List(events, selection: $selectedEventID) { projected in
            let event = projected.event
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Image(systemName: event.severity.symbolName)
                        .foregroundStyle(event.severity.tint)
                        .accessibilityHidden(true)
                    Text(diagnosticsTechnicalText(event.actionID, reason: .technicalIdentifier))
                        .font(.callout.monospaced())
                        .lineLimit(1)
                }
                Text(diagnosticsTechnicalText(
                    "#\(event.sequenceNumber) \u{00b7} \(event.phase) \u{00b7} \(event.outcome)"
                ))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .tag(Optional(projected.id))
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
        }
        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        .accessibilityLabel(L10n.string("observability.inspector.eventList"))
    }

    @ViewBuilder
    private var detail: some View {
        if let projected = selectedEvent {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if isOfflinePackage {
                        Label(
                            L10n.string("observability.inspector.offlineNotice"),
                            systemImage: "checkmark.shield"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    identitySection(projected.event)
                    classificationSection(projected)
                    timeSection(projected.event)
                    signpostSection(projected.event)
                    errorSection(projected.event.error)
                    attributesSection(projected.event.attributes)
                    resourcesSection(projected.event.resources)
                    buildSection(projected.event.buildContext)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            DiagnosticsConsoleEmptyView()
        }
    }

    private var selectedEvent: DiagnosticsProjectedEvent? {
        events.first { $0.id == selectedEventID }
    }

    private func identitySection(_ event: ObservabilityEventSnapshot) -> some View {
        DiagnosticsInspectorSection(title: L10n.string("observability.inspector.identity")) {
            DiagnosticsInspectorRow(label: technicalField("event_id"), value: event.eventID)
            DiagnosticsInspectorRow(label: L10n.string("observability.field.session"), value: event.sessionID)
            DiagnosticsInspectorRow(label: L10n.string("observability.field.incident"), value: event.incidentID)
            DiagnosticsInspectorRow(label: L10n.string("observability.field.trace"), value: event.traceID)
            DiagnosticsInspectorRow(label: L10n.string("observability.field.operation"), value: event.operationID)
            DiagnosticsInspectorRow(
                label: technicalField("retry_of_operation_id"),
                value: event.retryOfOperationID
            )
            DiagnosticsInspectorRow(label: technicalField("span_id"), value: event.spanID)
            DiagnosticsInspectorRow(
                label: technicalField("parent_span_id"),
                value: event.parentSpanID
            )
        }
    }

    private func classificationSection(_ projected: DiagnosticsProjectedEvent) -> some View {
        let event = projected.event
        return DiagnosticsInspectorSection(title: L10n.string("observability.inspector.classification")) {
            DiagnosticsInspectorRow(label: L10n.string("observability.field.action"), value: event.actionID)
            DiagnosticsInspectorRow(
                label: technicalField("action_group"),
                value: projected.actionGroup
            )
            DiagnosticsInspectorRow(label: L10n.string("observability.field.component"), value: event.componentID)
            DiagnosticsInspectorRow(label: technicalField("layer"), value: event.layer)
            DiagnosticsInspectorRow(label: L10n.string("observability.field.phase"), value: event.phase)
            DiagnosticsInspectorRow(label: L10n.string("observability.field.severity"), value: event.severity.rawValue)
            DiagnosticsInspectorRow(label: L10n.string("observability.field.outcome"), value: event.outcome)
            DiagnosticsInspectorRow(label: technicalField("privacy_level"), value: event.privacy)
            DiagnosticsInspectorRow(label: technicalField("thread_name"), value: event.threadName)
            DiagnosticsInspectorRow(
                label: L10n.string("observability.field.duration"),
                value: event.durationMilliseconds.map { "\($0) ms" }
            )
        }
    }

    private func timeSection(_ event: ObservabilityEventSnapshot) -> some View {
        DiagnosticsInspectorSection(title: L10n.string("observability.inspector.time")) {
            DiagnosticsInspectorRow(
                label: technicalField("wall_timestamp"),
                value: Self.iso8601.string(from: Date(
                    timeIntervalSince1970: Double(event.wallTimestampMilliseconds) / 1000
                ))
            )
            DiagnosticsInspectorRow(
                label: technicalField("wall_timestamp_ms"),
                value: String(event.wallTimestampMilliseconds)
            )
            DiagnosticsInspectorRow(
                label: technicalField("monotonic_timestamp_ns"),
                value: String(event.monotonicTimestampNanoseconds)
            )
            DiagnosticsInspectorRow(
                label: technicalField("sequence_number"),
                value: String(event.sequenceNumber)
            )
            DiagnosticsInspectorRow(
                label: technicalField("schema_version"),
                value: String(event.schemaVersion)
            )
        }
    }

    private func signpostSection(_ event: ObservabilityEventSnapshot) -> some View {
        DiagnosticsInspectorSection(title: L10n.string("observability.inspector.signpost")) {
            if let correlation = ObservabilitySignpostSink.correlation(for: event) {
                DiagnosticsInspectorRow(
                    label: technicalField("signpost_registration"),
                    value: correlation.registration.rawValue
                )
                DiagnosticsInspectorRow(
                    label: technicalField("instruments_category"),
                    value: correlation.category
                )
                DiagnosticsInspectorRow(label: technicalField("span_id"), value: correlation.spanID)
                DiagnosticsInspectorRow(
                    label: technicalField("correlation_key"),
                    value: correlation.correlationKey
                )
                Text(L10n.string("observability.inspector.signpostNotice"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("observability.inspector.noSignpost"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func errorSection(_ error: ObservabilityErrorSnapshot?) -> some View {
        if let error {
            DiagnosticsInspectorSection(title: L10n.string("observability.inspector.error")) {
                DiagnosticsInspectorRow(label: technicalField("error.code"), value: error.code)
                DiagnosticsInspectorRow(label: technicalField("error.kind"), value: error.kind)
                DiagnosticsInspectorRow(
                    label: technicalField("error.technical_details"),
                    value: error.technicalDetails
                )
            }
        }
    }

    @ViewBuilder
    private func attributesSection(_ attributes: [ObservabilityAttributeSnapshot]) -> some View {
        if !attributes.isEmpty {
            DiagnosticsInspectorSection(title: L10n.string("observability.inspector.attributes")) {
                ForEach(Array(attributes.enumerated()), id: \.offset) { _, attribute in
                    VStack(alignment: .leading, spacing: 5) {
                        DiagnosticsInspectorRow(
                            label: technicalField("attribute.key"),
                            value: attribute.key
                        )
                        DiagnosticsInspectorRow(
                            label: technicalField("attribute.value"),
                            value: attribute.value
                        )
                        DiagnosticsInspectorRow(
                            label: technicalField("attribute.privacy"),
                            value: attribute.privacy
                        )
                    }
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private func resourcesSection(_ resources: [ObservabilityResourceSnapshot]) -> some View {
        if !resources.isEmpty {
            DiagnosticsInspectorSection(title: L10n.string("observability.inspector.resources")) {
                ForEach(Array(resources.enumerated()), id: \.offset) { _, resource in
                    VStack(alignment: .leading, spacing: 5) {
                        DiagnosticsInspectorRow(
                            label: technicalField("resource_id"),
                            value: resource.resourceID
                        )
                        DiagnosticsInspectorRow(label: technicalField("alias"), value: resource.alias)
                        DiagnosticsInspectorRow(
                            label: technicalField("path_extension"),
                            value: resource.pathExtension
                        )
                        DiagnosticsInspectorRow(
                            label: technicalField("size_bucket"),
                            value: resource.sizeBucket
                        )
                        DiagnosticsInspectorRow(
                            label: technicalField("storage_mode"),
                            value: resource.storageMode
                        )
                    }
                    Divider()
                }
            }
        }
    }

    private func buildSection(_ context: ObservabilityBuildContextSnapshot?) -> some View {
        DiagnosticsInspectorSection(title: L10n.string("observability.inspector.build")) {
            if let context {
                DiagnosticsInspectorRow(label: technicalField("producer"), value: context.producer)
                DiagnosticsInspectorRow(label: technicalField("version"), value: context.version)
                DiagnosticsInspectorRow(label: technicalField("build"), value: context.build)
                DiagnosticsInspectorRow(
                    label: technicalField("configuration"),
                    value: context.configuration
                )
                DiagnosticsInspectorRow(label: technicalField("platform"), value: context.platform)
                DiagnosticsInspectorRow(
                    label: technicalField("architecture"),
                    value: context.architecture
                )
            } else {
                Text(L10n.string("observability.inspector.legacyBuild"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private func technicalField(_ value: String) -> String {
        diagnosticsTechnicalText(value, reason: .technicalIdentifier)
    }
}

private struct DiagnosticsInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            Divider()
            content
        }
    }
}

private struct DiagnosticsInspectorRow: View {
    let label: String
    let value: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 168, alignment: .leading)
            Text(diagnosticsTechnicalText(value ?? "-"))
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
