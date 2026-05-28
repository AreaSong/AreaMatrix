import SwiftUI

struct SearchFilterChipsBar: View {
    @Binding var filters: SearchFilterStateSnapshot

    var body: some View {
        let chips = SearchFilterChips.items(for: filters)
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button {
                            filters = SearchFilterEditing.removing(chip.kind, from: filters)
                        } label: {
                            Label(chip.label, systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Remove filter \(chip.label)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(chips.count) active filters")
        }
    }
}

struct LocalModelStatusBanner: View {
    let feedback: LocalModelStatusFeedback?
    let phase: LocalModelStatusPhase

    var body: some View {
        switch (feedback, phase) {
        case let (.success(message), _):
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .padding(12)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
        case let (.failed(error), _):
            failureBanner(error)
        case let (nil, .failed(error)):
            failureBanner(error)
        case let (_, .checking(message)):
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(message)
            }
            .padding(12)
            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        default:
            EmptyView()
        }
    }

    private func failureBanner(_ error: LocalModelStatusError) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(error.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(error.recovery)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
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
                summary: model.snapshot?.diagnosticsSummary ?? "Local model status has not been checked yet.",
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
        AdvancedSettingsSection(title: "Status") {
            Label(model.statusText, systemImage: statusIcon)
                .font(.headline)
                .accessibilityIdentifier("S3-02-C3-02-status")
            Text(model.statusDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
            AdvancedSettingsKeyValueRow(label: "Model", value: model.modelID)
            AdvancedSettingsKeyValueRow(label: "Version", value: model.snapshot?.version ?? "Unknown")
            AdvancedSettingsKeyValueRow(label: "Storage", value: model.storageLocation)
            AdvancedSettingsKeyValueRow(label: "Disk usage", value: model.formattedSize)
            AdvancedSettingsKeyValueRow(label: "Last checked", value: model.lastCheckedLabel)
            if let lastError = model.snapshot?.lastError, !lastError.isEmpty {
                AdvancedSettingsKeyValueRow(label: "Last error", value: lastError)
            }
            if let reason = model.repairUnavailableReason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var supportSection: some View {
        AdvancedSettingsSection(title: "Feature support") {
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
        AdvancedSettingsSection(title: "Actions") {
            HStack(spacing: 10) {
                Button(primaryStatusButtonTitle) {
                    Task { await model.checkStatus() }
                }
                .disabled(model.isChecking)
                .accessibilityIdentifier("S3-02-C3-02-check-status")

                Button("Open install help", action: model.openInstallHelp)
                    .disabled(model.isChecking)
                    .accessibilityIdentifier("S3-02-C3-02-open-install-help")
                Button("Open model location") {
                    Task { await model.openModelLocation() }
                }
                .disabled(!model.canOpenModelLocation)
                .accessibilityIdentifier("S3-02-C3-02-open-model-location")
            }
            HStack(spacing: 10) {
                Button("Run health check") {
                    Task { await model.checkStatus() }
                }
                .disabled(!model.canRunHealthCheck)
                Button("Repair", action: {})
                    .disabled(true)
                Button("Open diagnostics", action: model.showDiagnostics)
                    .accessibilityIdentifier("S3-02-C3-02-open-diagnostics")
            }
            Text("Status checks and diagnostics use only C3-02 local model metadata and do not enable remote AI.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryStatusButtonTitle: String {
        model.snapshot == nil ? "Check status" : "Retry status check"
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
            Text(status.available ? "Available" : status.unavailableReason ?? "Unavailable")
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

enum SearchFilterStateRouting {
    static func effective(
        searchFilters: SearchFilterStateSnapshot,
        draft: SmartListFilterDraft?
    ) -> SearchFilterStateSnapshot {
        draft?.filters ?? searchFilters
    }

    @MainActor
    static func assign(
        _ filters: SearchFilterStateSnapshot,
        searchFilters: inout SearchFilterStateSnapshot,
        fileListModel: MainFileListModel
    ) {
        if fileListModel.isEditingSmartListFilterDraft {
            fileListModel.updateSmartListFilterDraft(filters)
            return
        }
        searchFilters = filters
    }
}
