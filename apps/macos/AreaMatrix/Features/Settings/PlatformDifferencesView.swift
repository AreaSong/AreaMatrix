import SwiftUI

struct PlatformDifferencesView: View {
    @StateObject private var model: PlatformDifferencesModel
    private let onOpenRepositorySettings: () -> Void
    private let onClose: () -> Void

    @MainActor
    init(
        repositoryText: String = L10n.string("Not connected"),
        onOpenRepositorySettings: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: PlatformDifferencesModel(repositoryText: repositoryText))
        self.onOpenRepositorySettings = onOpenRepositorySettings
        self.onClose = onClose
    }

    init(
        model: PlatformDifferencesModel,
        onOpenRepositorySettings: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: model)
        self.onOpenRepositorySettings = onOpenRepositorySettings
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summary
            capabilityContent
            targetControls
            contractContent
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await model.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Platform capabilities")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Capability matrix and binding contract")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlatformDifferencesKeyValueRow(label: L10n.string("Platform"), value: model.hostPlatform.displayName)
            PlatformDifferencesKeyValueRow(label: L10n.string("Repository"), value: model.repositoryText)
            PlatformDifferencesKeyValueRow(label: L10n.string("App version"), value: model.appVersion)
            PlatformDifferencesKeyValueRow(label: L10n.string("Core version"), value: coreVersionText)
            Text("Capability matrix does not replace operation-time permission checks.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var targetControls: some View {
        HStack(alignment: .center, spacing: 12) {
            Picker("Binding target", selection: selectedTargetBinding) {
                ForEach(BindingTargetPlatformSnapshot.allCases, id: \.self) { targetPlatform in
                    Text(targetPlatform.displayName).tag(targetPlatform)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .accessibilityIdentifier("platform-differences-binding-contract-target-picker")

            Button {
                Task {
                    await model.inspectContract()
                }
            } label: {
                Label(model.contractActionTitle, systemImage: "checkmark.seal")
            }
            .disabled(model.isInspectingContract)
            .accessibilityIdentifier("platform-differences-binding-contract-check-contract")
        }
    }

    @ViewBuilder
    private var capabilityContent: some View {
        switch model.capabilityState {
        case .loading:
            SettingsInlineProgressStatus(title: L10n.string("Checking platform capabilities..."))
        case let .loaded(capabilities):
            capabilityMatrix(capabilities)
        case let .failed(capabilities, error):
            capabilityMatrix(capabilities)
            PlatformDifferencesCapabilityErrorBanner(error: error)
        }
    }

    @ViewBuilder
    private var contractContent: some View {
        switch model.contractState {
        case .loading:
            SettingsInlineProgressStatus(title: L10n.string("Checking binding contract..."))
        case let .loaded(report):
            contractReport(report)
        case let .failed(error):
            PlatformDifferencesErrorBanner(error: error)
        }
    }

    private func capabilityMatrix(_ capabilities: PlatformCapabilitiesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capability matrix")
                .font(.subheadline.weight(.semibold))
            ForEach(capabilities.pageSpecRows) { row in
                PlatformDifferencesCapabilityRow(row: row)
            }
        }
    }

    private func contractReport(_ report: BindingContractReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PlatformDifferencesKeyValueRow(label: L10n.string("Target"), value: report.targetPlatform.displayName)
            PlatformDifferencesKeyValueRow(label: L10n.string("Contract version"), value: "\(report.bindingVersion)")
            PlatformDifferencesKeyValueRow(label: L10n.string("Core version"), value: report.coreVersion)
            contractRows(title: L10n.string("Supported APIs"), rows: report.supportedApis.map {
                PlatformDifferencesStatusRow(
                    title: $0.name,
                    detail: $0.capability,
                    status: $0.status,
                    reason: $0.reason
                )
            })
            contractRows(title: L10n.string("Type mappings"), rows: report.typeMappings.map {
                PlatformDifferencesStatusRow(
                    title: "\($0.rustType) -> \($0.targetType)",
                    detail: $0.udlType,
                    status: $0.status,
                    reason: $0.reason
                )
            })
            missingCapabilityRows(report.missingCapabilities)
            Text("Read-only contract check. No repository files are opened or modified.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func contractRows(title: String, rows: [PlatformDifferencesStatusRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            ForEach(rows) { row in
                row
            }
        }
    }

    @ViewBuilder
    private func missingCapabilityRows(_ rows: [BindingMissingCapabilitySnapshot]) -> some View {
        if rows.isEmpty {
            Label("No missing binding capabilities for this target.", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.green)
        } else {
            contractRows(title: L10n.string("Limited or missing capabilities"), rows: rows.map {
                PlatformDifferencesStatusRow(
                    title: $0.label,
                    detail: $0.capability,
                    status: $0.status,
                    reason: $0.reason
                )
            })
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("Open repository settings", action: onOpenRepositorySettings)
                    .accessibilityIdentifier("platform-differences-open-repository-settings")
                Button("Export diagnostics") {}
                    .disabled(true)
                    .help("Diagnostics are not available on this platform yet.")
                    .accessibilityIdentifier("platform-differences-export-diagnostics")
                Button("Close", action: onClose)
                    .accessibilityIdentifier("platform-differences-close")
            }
            Text("Diagnostics are not available on this platform yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var coreVersionText: String {
        switch model.contractState {
        case let .loaded(report):
            report.coreVersion
        default:
            L10n.string("Unknown")
        }
    }

    private var selectedTargetBinding: Binding<BindingTargetPlatformSnapshot> {
        Binding(
            get: { model.selectedTargetPlatform },
            set: { targetPlatform in
                model.selectTargetPlatform(targetPlatform)
                Task {
                    await model.inspectContract()
                }
            }
        )
    }
}
