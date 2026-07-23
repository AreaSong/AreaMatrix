import SwiftUI

struct LocalModelStatusBanner: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let feedback: LocalModelStatusFeedback?
    let phase: LocalModelStatusPhase

    var body: some View {
        switch (feedback, phase) {
        case let (.success(message), _):
            TintedStatusBanner(tint: .green, fillsWidth: false) {
                Label(localizer.resolve(message), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
            .accessibilityElement(children: .combine)
        case let (.failed(error), _):
            failureBanner(error)
        case let (nil, .failed(error)):
            failureBanner(error)
        case let (_, .checking(message)):
            TintedStatusBanner(tint: .blue, fillsWidth: false) {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(localizer.resolve(message))
                }
            }
        default:
            EmptyView()
        }
    }

    private func failureBanner(_ error: LocalModelStatusError) -> some View {
        TintedStatusBanner(tint: .red, fillsWidth: false) {
            VStack(alignment: .leading, spacing: 6) {
                Label(localizer.resolve(error.message), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(localizer.resolve(error.recovery))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct LocalModelStatusView: View {
    @StateObject private var model: LocalModelStatusModel
    let onClose: () -> Void

    init(model: LocalModelStatusModel, onClose: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: model)
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LocalModelStatusBanner(feedback: model.feedback, phase: model.phase)
                    statusSection
                    supportSection
                    actionSection
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
            }
        }
        .frame(minWidth: 620, minHeight: 540, alignment: .topLeading)
        .sheet(isPresented: diagnosticsBinding) {
            LocalModelDiagnosticsView(
                summary: model.snapshot?.diagnosticsSummary ?? L10n
                    .string("Local model status has not been checked yet."),
                onCopy: model.copyDiagnosticsSummary,
                onBack: model.closeDiagnostics
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local model status")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(model.repoPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Close", action: onClose)
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var statusSection: some View {
        AdvancedSettingsSection(title: L10n.string("Status")) {
            Label(model.statusText, systemImage: statusIcon)
                .font(.headline)
                .accessibilityIdentifier("local-model-status-local-model-status-core-status")
            Text(model.statusDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
            AdvancedSettingsKeyValueRow(label: L10n.string("Model"), value: model.modelID)
            AdvancedSettingsKeyValueRow(
                label: L10n.string("Version"),
                value: model.snapshot?.version ?? L10n.string("Unknown")
            )
            AdvancedSettingsKeyValueRow(label: L10n.string("Storage"), value: model.storageLocation)
            AdvancedSettingsKeyValueRow(label: L10n.string("Disk usage"), value: model.formattedSize)
            AdvancedSettingsKeyValueRow(label: L10n.string("Last checked"), value: model.lastCheckedLabel)
            if let lastError = model.snapshot?.lastError, !lastError.isEmpty {
                AdvancedSettingsKeyValueRow(label: L10n.string("Last error"), value: lastError)
            }
            if let reason = model.repairUnavailableReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var supportSection: some View {
        AdvancedSettingsSection(title: L10n.string("Feature support")) {
            if model.snapshot?.featureStatuses.isEmpty != false {
                Text("Local feature support will appear after Check status returns a Core snapshot.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot?.featureStatuses ?? []) { status in
                    LocalModelFeatureRow(status: status)
                }
            }
        }
    }

    private var actionSection: some View {
        AdvancedSettingsSection(title: L10n.string("Actions")) {
            HStack(spacing: 10) {
                Button(primaryStatusButtonTitle) {
                    Task { await model.checkStatus() }
                }
                .disabled(model.isChecking)
                .accessibilityIdentifier("local-model-status-local-model-status-core-check-status")

                Button("Open install help", action: model.openInstallHelp)
                    .disabled(model.isChecking)
                    .accessibilityIdentifier("local-model-status-local-model-status-core-open-install-help")
                Button("Open model location") {
                    Task { await model.openModelLocation() }
                }
                .disabled(!model.canOpenModelLocation)
                .accessibilityIdentifier("local-model-status-local-model-status-core-open-model-location")
            }
            HStack(spacing: 10) {
                Button("Run health check") {
                    Task { await model.checkStatus() }
                }
                .disabled(!model.canRunHealthCheck)
                Button("Repair", action: {})
                    .disabled(true)
                Button("Open diagnostics", action: model.showDiagnostics)
                    .accessibilityIdentifier("local-model-status-local-model-status-core-open-diagnostics")
            }
            Text(L10n.string(
                "Status checks and diagnostics use only local model metadata and do not enable remote AI."
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var primaryStatusButtonTitle: String {
        model.snapshot == nil ? L10n.string("Check status") : L10n.string("Retry status check")
    }

    private var statusIcon: String {
        switch model.snapshot?.availability {
        case .ready:
            "checkmark.circle"
        case .notInstalled, .pathUnreadable, .versionIncompatible, .corrupted, .runtimeFailed, .error:
            "exclamationmark.triangle"
        case .checking, .verifying, .loading:
            "clock"
        default:
            "questionmark.circle"
        }
    }

    private var diagnosticsBinding: Binding<Bool> {
        Binding(
            get: { model.isDiagnosticsPresented },
            set: { if !$0 { model.closeDiagnostics() } }
        )
    }
}

struct LocalModelFeatureRow: View {
    let status: LocalModelFeatureStatusState

    var body: some View {
        HStack {
            Label(status.feature.title, systemImage: status.available ? "checkmark.circle" : "minus.circle")
            Spacer()
            Text(status.available ? L10n.string("Available") : status.unavailableReason ?? L10n.string("Unavailable"))
                .foregroundStyle(status.available ? Color.green : Color.secondary)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

struct LocalModelDiagnosticsView: View {
    let summary: String
    let onCopy: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Local model diagnostics")
                .font(.title2.weight(.semibold))
            Text(summary)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button("Copy diagnostics summary", action: onCopy)
                Spacer()
                Button("Back to local model status", action: onBack)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
