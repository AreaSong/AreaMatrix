import SwiftUI

struct DiagnosticsExpectedActualView: View {
    let projection: DiagnosticsExpectedActualProjection

    var body: some View {
        switch projection.state {
        case .ambiguousFlow:
            ContentUnavailableView(
                L10n.string("observability.console.ambiguousFlow"),
                systemImage: "arrow.triangle.branch"
            )
        case .catalogUnavailable:
            ContentUnavailableView(
                L10n.string("observability.console.catalogUnavailable"),
                systemImage: "exclamationmark.triangle"
            )
        case .flowUnavailable:
            ContentUnavailableView(
                L10n.string("observability.console.noCatalogMatch"),
                systemImage: "list.bullet.clipboard"
            )
        case .legacyPackage:
            ContentUnavailableView(
                L10n.string("observability.console.legacyFlowUnavailable"),
                systemImage: "clock.arrow.circlepath"
            )
        case .operationRequired:
            ContentUnavailableView(
                L10n.string("observability.console.selectOperation"),
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        case .ready:
            HSplitView {
                expectedColumn
                actualColumn
            }
        }
    }

    private var expectedColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            comparisonHeader(L10n.string("observability.console.expected"))
            Divider()
            List(projection.expected) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: expectedSymbol(row))
                        .foregroundStyle(expectedColor(row))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnosticsTechnicalText(row.value))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Text(DiagnosticsCatalogPresentation.requirement(row.required))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 360)
    }

    private var actualColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            comparisonHeader(L10n.string("observability.console.actual"))
            Divider()
            List(projection.actual) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.matchedStepIDs.isEmpty
                        ? "exclamationmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle(row.matchedStepIDs.isEmpty ? Color.orange : Color.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnosticsTechnicalText(row.value))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        if !row.matchedStepIDs.isEmpty {
                            Text(diagnosticsTechnicalText(
                                row.matchedStepIDs.joined(separator: ", "),
                                reason: .technicalIdentifier
                            ))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 360)
    }

    private func comparisonHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            if let flowID = projection.flowID {
                Text(diagnosticsTechnicalText(flowID, reason: .technicalIdentifier))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func expectedSymbol(_ row: DiagnosticsExpectedStepRow) -> String {
        if row.matchedEventID != nil { return "checkmark.circle.fill" }
        return row.required ? "exclamationmark.circle" : "circle.dashed"
    }

    private func expectedColor(_ row: DiagnosticsExpectedStepRow) -> Color {
        if row.matchedEventID != nil { return .green }
        return row.required ? .orange : .secondary
    }
}

enum DiagnosticsCatalogPresentation {
    static func title(for actionGroup: String?) -> LocalizedMessage {
        switch actionGroup {
        case "repository.import.duplicate.detected":
            L10n.message("observability.catalog.importDuplicate.title")
        case "repository.file.trash.fallback":
            L10n.message("observability.catalog.trashFallback.title")
        case "repository.import": L10n.message("observability.catalog.import.title")
        case "app.command": L10n.message("observability.catalog.command.title")
        case "diagnostics.export": L10n.message("observability.catalog.diagnosticExport.title")
        case "observability.runtime": L10n.message("observability.catalog.runtime.title")
        default: L10n.message("observability.activity.other")
        }
    }

    static func detail(for actionGroup: String) -> LocalizedMessage {
        switch actionGroup {
        case "repository.import.duplicate.detected":
            L10n.message("observability.catalog.importDuplicate.detail")
        case "repository.file.trash.fallback":
            L10n.message("observability.catalog.trashFallback.detail")
        case "repository.import": L10n.message("observability.catalog.import.detail")
        case "app.command": L10n.message("observability.catalog.command.detail")
        case "diagnostics.export": L10n.message("observability.catalog.diagnosticExport.detail")
        case "observability.runtime": L10n.message("observability.catalog.runtime.detail")
        default: L10n.message("observability.activity.other")
        }
    }

    static func trigger(for actionGroup: String) -> LocalizedMessage {
        switch actionGroup {
        case "repository.import.duplicate.detected":
            L10n.message("observability.catalog.importDuplicate.trigger")
        case "repository.file.trash.fallback":
            L10n.message("observability.catalog.trashFallback.trigger")
        case "repository.import": L10n.message("observability.catalog.import.trigger")
        case "app.command": L10n.message("observability.catalog.command.trigger")
        case "diagnostics.export": L10n.message("observability.catalog.diagnosticExport.trigger")
        case "observability.runtime": L10n.message("observability.catalog.runtime.trigger")
        default: L10n.message("observability.activity.other")
        }
    }

    static func owner(_ owner: String) -> String {
        switch owner {
        case "core": L10n.string("observability.catalog.owner.core")
        case "macos": L10n.string("observability.catalog.owner.macos")
        default: diagnosticsTechnicalText(owner, reason: .technicalIdentifier)
        }
    }

    static func role(_ role: String) -> String {
        switch role {
        case "runtime": L10n.string("observability.catalog.component.runtime.role")
        case "dedup": L10n.string("observability.catalog.component.dedup.role")
        case "import_stage": L10n.string("observability.catalog.component.importStage.role")
        case "overview": L10n.string("observability.catalog.component.overview.role")
        case "trash": L10n.string("observability.catalog.component.trash.role")
        case "ui": L10n.string("observability.catalog.component.macosUI.role")
        case "bridge", "import", "import_ui": L10n.string("observability.catalog.component.import.role")
        default: diagnosticsTechnicalText(role, reason: .technicalIdentifier)
        }
    }

    static func requirement(_ required: Bool) -> String {
        if required { return L10n.string("observability.console.required") }
        return L10n.string("observability.console.optional")
    }
}

struct DiagnosticsCatalogView: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let catalog: ObservabilityCatalog?
    let searchText: String

    var body: some View {
        if let catalog {
            HSplitView {
                actionsColumn(catalog)
                flowsColumn(catalog)
                componentsColumn(catalog)
            }
        } else {
            ContentUnavailableView(
                L10n.string("observability.console.catalogUnavailable"),
                systemImage: "exclamationmark.triangle"
            )
        }
    }

    private func actionsColumn(_ catalog: ObservabilityCatalog) -> some View {
        catalogColumn(title: L10n.string("observability.catalog.actions")) {
            ForEach(filteredActions(catalog), id: \.id) { action in
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.resolve(DiagnosticsCatalogPresentation.title(for: action.group)))
                        .font(.headline)
                    Text(diagnosticsTechnicalText(action.id, reason: .technicalIdentifier))
                        .font(.caption.monospaced())
                    Text(localizer.resolve(DiagnosticsCatalogPresentation.detail(for: action.group)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(localizer.resolve(DiagnosticsCatalogPresentation.trigger(for: action.group)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func flowsColumn(_ catalog: ObservabilityCatalog) -> some View {
        catalogColumn(title: L10n.string("observability.console.expected")) {
            ForEach(filteredFlows(catalog), id: \.id) { flow in
                DisclosureGroup {
                    ForEach(flow.steps, id: \.id) { step in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(diagnosticsTechnicalText(step.id, reason: .technicalIdentifier))
                                .font(.callout.monospaced())
                            Text(DiagnosticsCatalogPresentation.requirement(step.required))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                } label: {
                    Text(diagnosticsTechnicalText(flow.id, reason: .technicalIdentifier))
                        .font(.headline.monospaced())
                }
            }
        }
    }

    private func componentsColumn(_ catalog: ObservabilityCatalog) -> some View {
        catalogColumn(title: L10n.string("observability.catalog.components")) {
            ForEach(filteredComponents(catalog), id: \.id) { component in
                VStack(alignment: .leading, spacing: 4) {
                    Text(diagnosticsTechnicalText(component.id, reason: .technicalIdentifier))
                        .font(.headline.monospaced())
                    Text(DiagnosticsCatalogPresentation.role(component.role)).font(.callout)
                    Text(DiagnosticsCatalogPresentation.owner(component.owner))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(diagnosticsTechnicalText(component.symbol)).font(.caption.monospaced())
                    Text(diagnosticsTechnicalText(component.authority)).font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 5)
            }
        }
    }

    private func catalogColumn(
        title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding()
            Divider()
            List { content() }
        }
        .frame(minWidth: 300)
    }

    private func filteredActions(_ catalog: ObservabilityCatalog) -> [ObservabilityCatalog.Action] {
        guard !searchText.isEmpty else { return catalog.actions }
        return catalog.actions.filter {
            "\($0.id) \($0.group)".localizedCaseInsensitiveContains(searchText)
        }
    }

    private func filteredFlows(_ catalog: ObservabilityCatalog) -> [ObservabilityCatalog.ExpectedFlow] {
        guard !searchText.isEmpty else { return catalog.expectedFlows }
        return catalog.expectedFlows.filter { flow in
            ([flow.id] + flow.entryActionIDs + flow.steps.map(\.id))
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(searchText)
        }
    }

    private func filteredComponents(_ catalog: ObservabilityCatalog) -> [ObservabilityCatalog.Component] {
        guard !searchText.isEmpty else { return catalog.components }
        return catalog.components.filter {
            "\($0.id) \($0.owner) \($0.role) \($0.symbol) \($0.authority)"
                .localizedCaseInsensitiveContains(searchText)
        }
    }
}
