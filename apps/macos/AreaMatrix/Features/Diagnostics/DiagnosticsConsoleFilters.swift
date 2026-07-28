import SwiftUI

struct DiagnosticsConsoleFilterBar: View {
    @Binding var filters: DiagnosticsFilterState
    let options: DiagnosticsFilterOptions

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(L10n.string("observability.console.search"), text: $filters.searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.string("observability.console.search"))
                clearButton
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    optionalPicker(L10n.string("observability.field.session"), selection: $filters.sessionID,
                                   values: options.sessionIDs)
                    optionalPicker(L10n.string("observability.field.incident"), selection: $filters.incidentID,
                                   values: options.incidentIDs)
                    optionalPicker(L10n.string("observability.field.trace"), selection: $filters.traceID,
                                   values: options.traceIDs)
                    optionalPicker(L10n.string("observability.field.operation"), selection: $filters.operationID,
                                   values: options.operationIDs)
                    optionalPicker(L10n.string("observability.field.action"), selection: $filters.actionID,
                                   values: options.actionIDs)
                    optionalPicker(L10n.string("observability.field.component"), selection: $filters.componentID,
                                   values: options.componentIDs)
                    severityPicker
                    optionalPicker(L10n.string("observability.field.outcome"), selection: $filters.outcome,
                                   values: options.outcomes)
                    durationPicker
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var clearButton: some View {
        Button {
            filters.clear()
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.borderless)
        .disabled(!filters.isActive)
        .help(L10n.string("observability.filter.clear"))
        .accessibilityLabel(L10n.string("observability.filter.clear"))
    }

    private func optionalPicker(
        _ label: String,
        selection: Binding<String?>,
        values: [String]
    ) -> some View {
        Picker(label, selection: selection) {
            Text(L10n.string("observability.filter.all")).tag(nil as String?)
            ForEach(values, id: \.self) { value in
                Text(diagnosticsTechnicalText(value.diagnosticsShortTechnicalID, reason: .technicalIdentifier))
                    .tag(Optional(value))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(label)
    }

    private var severityPicker: some View {
        Picker(L10n.string("observability.field.severity"), selection: $filters.severity) {
            Text(L10n.string("observability.filter.all")).tag(nil as AppObservabilitySeverity?)
            ForEach(options.severities, id: \.rawValue) { severity in
                Text(diagnosticsTechnicalText(severity.rawValue, reason: .technicalIdentifier))
                    .tag(Optional(severity))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(L10n.string("observability.field.severity"))
    }

    private var durationPicker: some View {
        Picker(L10n.string("observability.field.duration"), selection: $filters.duration) {
            Text(L10n.string("observability.filter.all")).tag(nil as DiagnosticsDurationFilter?)
            ForEach(DiagnosticsDurationFilter.allCases, id: \.self) { duration in
                Text(duration.label).tag(Optional(duration))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(L10n.string("observability.field.duration"))
    }
}

private extension DiagnosticsDurationFilter {
    var label: String {
        switch self {
        case .underTen: L10n.string("observability.filter.duration.underTen")
        case .tenToHundred: L10n.string("observability.filter.duration.tenToHundred")
        case .hundredToThousand: L10n.string("observability.filter.duration.hundredToThousand")
        case .overThousand: L10n.string("observability.filter.duration.overThousand")
        case .unknown: L10n.string("observability.filter.duration.unknown")
        }
    }
}
