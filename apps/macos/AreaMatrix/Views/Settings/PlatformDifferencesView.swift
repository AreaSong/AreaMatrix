import SwiftUI

struct PlatformDifferencesView: View {
    @StateObject private var model: PlatformDifferencesModel

    @MainActor
    init() {
        _model = StateObject(wrappedValue: PlatformDifferencesModel())
    }

    init(model: PlatformDifferencesModel) {
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            targetControls
            contractContent
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
            Text("Binding contract")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var targetControls: some View {
        HStack(alignment: .center, spacing: 12) {
            Picker("Binding target", selection: selectedTargetBinding) {
                ForEach(BindingTargetPlatformSnapshot.allCases, id: \.self) { targetPlatform in
                    Text(targetPlatform.rawValue).tag(targetPlatform)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)
            .accessibilityIdentifier("S4-X-02-C4-01-target-picker")

            Button {
                Task {
                    await model.inspectContract()
                }
            } label: {
                Label(model.contractActionTitle, systemImage: "checkmark.seal")
            }
            .disabled(model.isInspectingContract)
            .accessibilityIdentifier("S4-X-02-C4-01-check-contract")
        }
    }

    @ViewBuilder
    private var contractContent: some View {
        switch model.contractState {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking binding contract...")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        case let .loaded(report):
            contractReport(report)
        case let .failed(error):
            PlatformDifferencesErrorBanner(error: error)
        }
    }

    private func contractReport(_ report: BindingContractReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PlatformDifferencesKeyValueRow(label: "Target", value: report.targetPlatform.rawValue)
            PlatformDifferencesKeyValueRow(label: "Contract version", value: "\(report.bindingVersion)")
            PlatformDifferencesKeyValueRow(label: "Core version", value: report.coreVersion)
            contractRows(title: "Supported APIs", rows: report.supportedApis.map {
                PlatformDifferencesStatusRow(
                    title: $0.name,
                    detail: $0.capability,
                    status: $0.status,
                    reason: $0.reason
                )
            })
            contractRows(title: "Type mappings", rows: report.typeMappings.map {
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
            contractRows(title: "Limited or missing capabilities", rows: rows.map {
                PlatformDifferencesStatusRow(
                    title: $0.label,
                    detail: $0.capability,
                    status: $0.status,
                    reason: $0.reason
                )
            })
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

private struct PlatformDifferencesKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct PlatformDifferencesStatusRow: View, Identifiable {
    let title: String
    let detail: String
    let status: BindingSupportStatusSnapshot
    let reason: String?

    var id: String {
        "\(title)-\(detail)-\(status.rawValue)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.callout)
                    .textSelection(.enabled)
                Spacer()
                Text(status.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusTint.opacity(0.12), in: Capsule())
                    .foregroundStyle(statusTint)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var statusTint: Color {
        switch status {
        case .supported:
            .green
        case .limited:
            .orange
        case .missing:
            .red
        }
    }
}

private struct PlatformDifferencesErrorBanner: View {
    let error: PlatformDifferencesContractError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
