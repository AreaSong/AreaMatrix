import SwiftUI

struct DiagnosticsIncidentSection: View {
    let incidents: [ObservabilityIncidentSnapshot]
    let selection: Binding<String>
    let note: Binding<String>
    let isBusy: Bool
    let onMark: () -> Void
    let onUpdateStatus: (ObservabilityIncidentStatus) -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsFormSection(title: L10n.string("observability.incident.title")) {
            Text(L10n.string("observability.incident.detail"))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField(L10n.string("observability.incident.note"), text: note)
                Button(action: onMark) {
                    Label(L10n.string("observability.incident.mark"), systemImage: "flag")
                }
                .disabled(isBusy)
            }
            if let incident = selectedIncident {
                Picker(L10n.string("observability.incident.selected"), selection: selection) {
                    ForEach(incidents) { value in
                        Text(value.id).tag(value.id)
                    }
                }
                Picker(L10n.string("observability.incident.status"), selection: statusBinding) {
                    ForEach(ObservabilityIncidentStatus.allCases, id: \.self) { status in
                        Text(status.localizedLabel).tag(status)
                    }
                }
                .frame(maxWidth: 280)
                LabeledContent(
                    L10n.string("observability.package.events"),
                    value: String(incident.events.count)
                )
                Button(role: .destructive, action: onDelete) {
                    Label(L10n.string("observability.incident.delete"), systemImage: "trash")
                }
                .disabled(isBusy)
                LabeledContent(
                    L10n.string("observability.incident.capture"),
                    value: incident.isFrozen
                        ? L10n.string("observability.incident.frozen")
                        : L10n.string("observability.incident.capturing")
                )
            } else {
                Text(L10n.string("observability.incident.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedIncident: ObservabilityIncidentSnapshot? {
        incidents.first { $0.id == selection.wrappedValue }
    }

    private var statusBinding: Binding<ObservabilityIncidentStatus> {
        Binding(
            get: { selectedIncident?.status ?? .open },
            set: onUpdateStatus
        )
    }
}

struct DiagnosticsPackageSection: View {
    let scope: Binding<DiagnosticsPackageScope>
    let incidents: [ObservabilityIncidentSnapshot]
    let incidentSelection: Binding<String>
    let includeSensitiveEvents: Binding<Bool>
    let includeFileNames: Binding<Bool>
    let includeFullPaths: Binding<Bool>
    let includeMetadataSnapshot: Binding<Bool>
    let isBusy: Bool
    let onPreparePreview: () -> Void
    let onOpenPackage: () -> Void

    var body: some View {
        SettingsFormSection(title: L10n.string("observability.package.title")) {
            Picker(L10n.string("observability.package.scope"), selection: scope) {
                ForEach(DiagnosticsPackageScope.allCases, id: \.self) { value in
                    Text(value.label).tag(value)
                }
            }
            .pickerStyle(.segmented)
            if scope.wrappedValue == .selectedIncident {
                Picker(L10n.string("observability.incident.selected"), selection: incidentSelection) {
                    ForEach(incidents) { incident in
                        Text(incident.id).tag(incident.id)
                    }
                }
                .disabled(incidents.isEmpty)
            }
            Toggle(
                L10n.string("observability.package.includeSensitiveEvents"),
                isOn: includeSensitiveEvents
            )
            Toggle(
                L10n.string("observability.package.includeFileNames"),
                isOn: includeFileNames
            )
            Toggle(
                L10n.string("observability.package.includeFullPaths"),
                isOn: includeFullPaths
            )
            .disabled(!includeFileNames.wrappedValue)
            Toggle(
                L10n.string("observability.package.includeMetadataSnapshot"),
                isOn: includeMetadataSnapshot
            )
            HStack {
                Button(action: onPreparePreview) {
                    Label(L10n.string("observability.package.prepare"), systemImage: "eye")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || (scope.wrappedValue == .selectedIncident && incidents.isEmpty))
                Button(action: onOpenPackage) {
                    Label(L10n.string("observability.package.open"), systemImage: "shippingbox")
                }
                .disabled(isBusy)
            }
            Text(L10n.string("observability.package.localOnly"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct DiagnosticsPackagePreviewSheet: View {
    let summary: DiagnosticsPackagePreviewSummary
    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.string("observability.package.preview.title"))
                .font(.title2.weight(.semibold))
            Text(L10n.string("observability.package.preview.detail"))
                .foregroundStyle(.secondary)
            LabeledContent(L10n.string("observability.package.events"), value: String(summary.eventCount))
            LabeledContent(
                L10n.string("observability.package.estimatedSize"),
                value: ByteCountFormatter.string(fromByteCount: summary.estimatedSizeBytes, countStyle: .file)
            )
            LabeledContent(
                L10n.string("observability.package.redacted"),
                value: String(summary.redactedFieldCount)
            )
            LabeledContent(
                L10n.string("observability.package.rejected"),
                value: String(summary.rejectedEventCount)
            )
            LabeledContent(
                L10n.string("observability.package.sensitiveEvents"),
                value: summary.includesSensitiveEvents
                    ? L10n.string("settings.value.yes")
                    : L10n.string("settings.value.no")
            )
            LabeledContent(
                L10n.string("observability.package.fileNames"),
                value: summary.includesFileNames
                    ? L10n.string("settings.value.yes")
                    : L10n.string("settings.value.no")
            )
            LabeledContent(
                L10n.string("observability.package.fullPaths"),
                value: summary.includesFullPaths
                    ? L10n.string("settings.value.yes")
                    : L10n.string("settings.value.no")
            )
            LabeledContent(
                L10n.string("observability.package.metadataSnapshot"),
                value: summary.includesMetadataSnapshot
                    ? L10n.string("settings.value.yes")
                    : L10n.string("settings.value.no")
            )
            Text(L10n.string("observability.package.includedFiles")).font(.headline)
            ForEach(summary.includedFiles, id: \.self) { file in
                Text(file).font(.caption.monospaced()).textSelection(.enabled)
            }
            Spacer()
            HStack {
                Spacer()
                Button(L10n.string("settings.action.cancel"), action: onCancel)
                Button(L10n.string("observability.package.export"), action: onExport)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 560)
    }
}

extension AppObservabilityMode {
    var localizedLabel: String {
        switch self {
        case .disabled: L10n.string("observability.mode.disabled")
        case .standard: L10n.string("observability.mode.standard")
        case .diagnostic: L10n.string("observability.mode.diagnostic")
        case .developer: L10n.string("observability.mode.developer")
        }
    }

    var localizedDetail: String {
        switch self {
        case .disabled: L10n.string("observability.mode.disabled.detail")
        case .standard: L10n.string("observability.mode.standard.detail")
        case .diagnostic: L10n.string("observability.mode.diagnostic.detail")
        case .developer: L10n.string("observability.mode.developer.detail")
        }
    }
}

extension AppObservabilityExpiryPolicy {
    var localizedLabel: String {
        switch self {
        case .timed: L10n.string("observability.lease.timed")
        case .nextLaunch: L10n.string("observability.lease.nextLaunch")
        case .manual: L10n.string("observability.lease.manual")
        }
    }

    var localizedDetail: String {
        switch self {
        case .timed: L10n.string("observability.lease.timed.detail")
        case .nextLaunch: L10n.string("observability.lease.nextLaunch.detail")
        case .manual: L10n.string("observability.lease.manual.detail")
        }
    }
}

extension ObservabilityHealthIssue.Source {
    var localizedLabel: String {
        switch self {
        case .catalog: L10n.string("observability.health.source.catalog")
        case .core: L10n.string("observability.health.source.core")
        case .ingress: L10n.string("observability.health.source.ingress")
        case .resourceIdentity: L10n.string("observability.health.source.resourceIdentity")
        case .runtime: L10n.string("observability.health.source.runtime")
        case .session: L10n.string("observability.health.source.session")
        case .signpost: L10n.string("observability.health.source.signpost")
        case .writer: L10n.string("observability.health.source.writer")
        }
    }
}

extension AppObservabilitySeverity {
    var localizedLabel: String {
        switch self {
        case .trace: L10n.string("observability.severity.trace")
        case .debug: L10n.string("observability.severity.debug")
        case .info: L10n.string("observability.severity.info")
        case .warn: L10n.string("observability.severity.warn")
        case .error: L10n.string("observability.severity.error")
        }
    }

    var symbolName: String {
        switch self {
        case .trace, .debug: "ladybug"
        case .info: "info.circle"
        case .warn: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .trace, .debug: .secondary
        case .info: .blue
        case .warn: .orange
        case .error: .red
        }
    }
}

extension ObservabilityIncidentStatus {
    var localizedLabel: String {
        switch self {
        case .open: L10n.string("observability.incident.status.open")
        case .resolved: L10n.string("observability.incident.status.resolved")
        case .dismissed: L10n.string("observability.incident.status.dismissed")
        }
    }
}
