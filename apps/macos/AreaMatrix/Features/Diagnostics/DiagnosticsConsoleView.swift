import SwiftUI

struct DiagnosticsConsoleView: View {
    enum Projection: String, CaseIterable {
        case activity
        case developer
    }

    @Environment(\.dismiss) private var dismiss
    @State private var projection: Projection = .activity
    @State private var filters = DiagnosticsFilterState()
    @State private var filtered: DiagnosticsFilteredProjection

    private let source: DiagnosticsConsoleProjection
    private let sourceToken: DiagnosticsSourceToken
    let packageInspection: DiagnosticPackageInspection?
    let onRefresh: (() async -> Void)?
    let onMarkIncident: (() async -> Void)?

    init(
        events: [ObservabilityEventSnapshot],
        catalog: ObservabilityCatalog?,
        packageInspection: DiagnosticPackageInspection? = nil,
        onRefresh: (() async -> Void)? = nil,
        onMarkIncident: (() async -> Void)? = nil
    ) {
        let isLegacyPackage = packageInspection?.isLegacy == true
        let source = DiagnosticsConsoleProjection(
            events: events,
            catalog: catalog,
            flowEvaluationContext: isLegacyPackage ? .legacyPackage : .current
        )
        self.source = source
        sourceToken = DiagnosticsSourceToken(
            events: events,
            catalog: catalog,
            isLegacyPackage: isLegacyPackage
        )
        self.packageInspection = packageInspection
        self.onRefresh = onRefresh
        self.onMarkIncident = onMarkIncident
        _filtered = State(initialValue: source.filtered(using: .init()))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            DiagnosticsConsoleFilterBar(filters: $filters, options: source.options)
            Divider()
            consoleContent
        }
        .frame(minWidth: 1080, minHeight: 680)
        .onChange(of: filters) { _, value in filtered = source.filtered(using: value) }
        .onChange(of: sourceToken) { _, _ in filtered = source.filtered(using: filters) }
    }

    @ViewBuilder
    private var consoleContent: some View {
        if projection == .activity {
            DiagnosticsActivityList(events: filtered.events)
        } else {
            DiagnosticsDeveloperConsole(
                projection: filtered,
                catalog: source.catalogSnapshot,
                packageInspection: packageInspection,
                catalogSearchText: filters.searchText
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker(L10n.string("observability.console.projection"), selection: $projection) {
                Text(L10n.string("observability.console.activity")).tag(Projection.activity)
                Text(L10n.string("observability.console.developer")).tag(Projection.developer)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()
            if packageInspection != nil {
                Label(L10n.string("observability.package.offline"), systemImage: "shippingbox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if packageInspection?.isLegacy == true {
                Label(L10n.string("observability.package.legacy"), systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            markIncidentButton
            refreshButton
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .help(L10n.string("settings.action.close"))
            .accessibilityLabel(L10n.string("settings.action.close"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var markIncidentButton: some View {
        if let onMarkIncident {
            Button {
                Task { await onMarkIncident() }
            } label: {
                Image(systemName: "flag")
            }
            .help(L10n.string("observability.incident.markNow"))
            .accessibilityLabel(L10n.string("observability.incident.markNow"))
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if let onRefresh {
            Button {
                Task { await onRefresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L10n.string("observability.action.refresh"))
            .accessibilityLabel(L10n.string("observability.action.refresh"))
        }
    }
}

private struct DiagnosticsDeveloperConsole: View {
    enum Panel: String, CaseIterable, Hashable {
        case timeline
        case inspector
        case tree
        case causal
        case terminal
        case raw
        case comparison
        case diff
        case catalog
        case fingerprint
        case package
    }

    let projection: DiagnosticsFilteredProjection
    let catalog: ObservabilityCatalog?
    let packageInspection: DiagnosticPackageInspection?
    let catalogSearchText: String

    @State private var panel: Panel? = .timeline
    @State private var selectedTraceID = ""
    @State private var selectedOperationID = ""
    @State private var selectedEventID: String?
    @State private var comparisonTraceID = ""

    var body: some View {
        VStack(spacing: 0) {
            traceControls
            Divider()
            HSplitView {
                panelSidebar
                panelContent
            }
        }
        .onAppear(perform: synchronizeSelection)
        .onChange(of: projection.traceIDs) { _, _ in synchronizeSelection() }
        .onChange(of: selectedTraceID) { _, _ in synchronizeOperationSelection() }
        .onChange(of: selectedOperationID) { _, _ in synchronizeEventSelection() }
        .onChange(of: selectedEventIDs) { _, _ in synchronizeEventSelection() }
    }

    private var traceControls: some View {
        HStack(spacing: 12) {
            Picker(L10n.string("observability.field.trace"), selection: $selectedTraceID) {
                ForEach(projection.traceIDs, id: \.self) { traceID in
                    Text(diagnosticsTechnicalText(
                        traceID.diagnosticsShortTechnicalID,
                        reason: .technicalIdentifier
                    )).tag(traceID)
                }
            }
            .frame(width: 260)
            .disabled(projection.traceIDs.isEmpty)
            if let selectedTrace, !selectedTrace.operationIDs.isEmpty {
                Picker(L10n.string("observability.field.operation"), selection: $selectedOperationID) {
                    Text(L10n.string("observability.console.entireTrace")).tag("")
                    ForEach(selectedTrace.operationIDs, id: \.self) { operationID in
                        Text(diagnosticsTechnicalText(
                            operationID.diagnosticsShortTechnicalID,
                            reason: .technicalIdentifier
                        )).tag(operationID)
                    }
                }
                .frame(width: 260)
            }
            Text(L10n.format("observability.console.eventCount.format", selectedEvents.count))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var panelSidebar: some View {
        List(selection: $panel) {
            ForEach(availablePanels, id: \.self) { value in
                Label(value.label, systemImage: value.symbolName)
                    .tag(Optional(value))
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
        .accessibilityLabel(L10n.string("observability.console.developerPanel"))
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panel ?? .timeline {
        case .timeline:
            DiagnosticsTimelineView(events: selectedEvents)
        case .inspector:
            DiagnosticsEventInspectorView(
                events: selectedEvents,
                selectedEventID: $selectedEventID,
                isOfflinePackage: packageInspection != nil
            )
        case .tree:
            DiagnosticsTraceTreeView(rows: selectedTreeRows)
        case .causal:
            DiagnosticsCausalGraphView(projection: selectedCausal)
        case .terminal:
            DiagnosticsTerminalView(events: selectedEvents)
        case .raw:
            DiagnosticsRawEventsView(events: selectedEvents)
        case .comparison:
            DiagnosticsExpectedActualView(
                projection: selectedOperation?.expectedActual ?? .operationRequired
            )
        case .diff:
            DiagnosticsTraceDiffView(
                traces: projection.traces,
                traceIDs: projection.traceIDs,
                traceRevisionToken: projection.traceRevisionToken,
                baselineID: $selectedTraceID,
                comparisonID: $comparisonTraceID
            )
        case .catalog:
            DiagnosticsCatalogView(catalog: catalog, searchText: catalogSearchText)
        case .fingerprint:
            DiagnosticsFingerprintView(
                traceID: selectedTraceID,
                fingerprint: selectedOperation?.fingerprint ?? selectedTrace?.fingerprint ?? "-",
                eventCount: selectedEvents.count
            )
        case .package:
            if let packageInspection {
                DiagnosticsPackageOverview(inspection: packageInspection)
            } else {
                DiagnosticsConsoleEmptyView()
            }
        }
    }

    private var selectedTrace: DiagnosticsTraceData? {
        projection.traces[selectedTraceID]
    }

    private var selectedOperation: DiagnosticsOperationData? {
        guard !selectedOperationID.isEmpty else { return nil }
        return selectedTrace?.operations[selectedOperationID]
    }

    private var selectedEvents: [DiagnosticsProjectedEvent] {
        selectedOperation?.events ?? selectedTrace?.events ?? []
    }

    private var selectedTreeRows: [DiagnosticsSpanRow] {
        selectedOperation?.treeRows ?? selectedTrace?.treeRows ?? []
    }

    private var selectedEventIDs: [String] {
        selectedEvents.map(\.id)
    }

    private var selectedCausal: DiagnosticsCausalProjection {
        selectedOperation?.causal ?? selectedTrace?.causal ?? .init(nodes: [], edges: [])
    }

    private var availablePanels: [Panel] {
        packageInspection == nil ? Panel.allCases.filter { $0 != .package } : Panel.allCases
    }

    private func synchronizeSelection() {
        if !projection.traceIDs.contains(selectedTraceID) {
            selectedTraceID = projection.traceIDs.first ?? ""
        }
        if !projection.traceIDs.contains(comparisonTraceID) || comparisonTraceID == selectedTraceID {
            comparisonTraceID = projection.traceIDs.first { $0 != selectedTraceID } ?? selectedTraceID
        }
        synchronizeOperationSelection()
        if panel == .package, packageInspection == nil { panel = .timeline }
    }

    private func synchronizeOperationSelection() {
        guard let selectedTrace else {
            selectedOperationID = ""
            return
        }
        if !selectedTrace.operationIDs.contains(selectedOperationID) {
            selectedOperationID = selectedTrace.operationIDs.first ?? ""
        }
        synchronizeEventSelection()
    }

    private func synchronizeEventSelection() {
        if selectedEventID.map(selectedEventIDs.contains) != true {
            selectedEventID = selectedEventIDs.first
        }
    }
}

private struct DiagnosticsSourceToken: Equatable {
    let count: Int
    let revision: Int
    let catalog: ObservabilityCatalog?
    let isLegacyPackage: Bool

    init(
        events: [ObservabilityEventSnapshot],
        catalog: ObservabilityCatalog?,
        isLegacyPackage: Bool
    ) {
        count = events.count
        self.catalog = catalog
        self.isLegacyPackage = isLegacyPackage
        var hasher = Hasher()
        for event in events {
            hasher.combine(DiagnosticsRawEncoder.encode(event))
        }
        revision = hasher.finalize()
    }
}

private extension DiagnosticsDeveloperConsole.Panel {
    var label: String {
        switch self {
        case .timeline: L10n.string("observability.console.timeline")
        case .inspector: L10n.string("observability.console.inspector")
        case .tree: L10n.string("observability.console.tree")
        case .causal: L10n.string("observability.console.causal")
        case .terminal: L10n.string("observability.console.terminal")
        case .raw: L10n.string("observability.console.raw")
        case .comparison: L10n.string("observability.console.comparison")
        case .diff: L10n.string("observability.console.diff")
        case .catalog: L10n.string("observability.console.catalog")
        case .fingerprint: L10n.string("observability.console.fingerprint")
        case .package: L10n.string("observability.console.package")
        }
    }

    var symbolName: String {
        switch self {
        case .timeline: "clock.arrow.circlepath"
        case .inspector: "sidebar.right"
        case .tree: "point.3.connected.trianglepath.dotted"
        case .causal: "arrow.triangle.branch"
        case .terminal: "terminal"
        case .raw: "curlybraces"
        case .comparison: "checklist"
        case .diff: "arrow.left.arrow.right"
        case .catalog: "books.vertical"
        case .fingerprint: "number.square"
        case .package: "shippingbox"
        }
    }
}
