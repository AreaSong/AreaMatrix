import SwiftUI

struct DiagnosticsSettingsPane: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: DiagnosticsSettingsModel
    @State private var isApplyConfirmationPresented = false
    @State private var isDeleteConfirmationPresented = false
    @State private var isIncidentDeleteConfirmationPresented = false
    @State private var isSensitiveLoggingConfirmationPresented = false
    @State private var isSensitivePackageConfirmationPresented = false
    @State private var isFileNamePackageConfirmationPresented = false
    @State private var isFullPathPackageConfirmationPresented = false
    @State private var isMetadataSnapshotConfirmationPresented = false
    private let loadsAutomatically: Bool

    @MainActor
    init(repositoryURL: URL) {
        _model = StateObject(wrappedValue: DiagnosticsSettingsModel(repositoryURL: repositoryURL))
        loadsAutomatically = true
    }

    @MainActor
    init(model: DiagnosticsSettingsModel, loadsAutomatically: Bool = true) {
        _model = StateObject(wrappedValue: model)
        self.loadsAutomatically = loadsAutomatically
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                title: L10n.string("settings.page.diagnostics"),
                subtitle: L10n.string("observability.settings.subtitle")
            ) {
                if model.isBusy {
                    SettingsHeaderProgressIndicator(label: L10n.string("observability.status.refreshing"))
                } else {
                    Button {
                        Task { await model.refreshRuntimeState() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(L10n.string("observability.action.refresh"))
                    .accessibilityLabel(L10n.string("observability.action.refresh"))
                }
            }
            SettingsPageScrollContent {
                VStack(alignment: .leading, spacing: 24) {
                    feedbackBanner
                    modeSection
                    DiagnosticsHealthSection(health: model.health)
                    DiagnosticsIncidentSection(
                        incidents: model.incidents,
                        selection: $model.selectedIncidentID,
                        note: $model.incidentNote,
                        isBusy: model.isBusy,
                        onMark: { Task { await model.markIncident() } },
                        onUpdateStatus: { status in Task { await model.updateIncidentStatus(status) } },
                        onDelete: { isIncidentDeleteConfirmationPresented = true }
                    )
                    DiagnosticsPackageSection(
                        scope: $model.packageScope,
                        incidents: model.incidents,
                        incidentSelection: $model.selectedIncidentID,
                        includeSensitiveEvents: sensitivePackageBinding,
                        includeFileNames: fileNamePackageBinding,
                        includeFullPaths: fullPathPackageBinding,
                        includeMetadataSnapshot: metadataSnapshotBinding,
                        isBusy: model.isBusy,
                        onPreparePreview: { Task { await model.preparePackagePreview() } },
                        onOpenPackage: model.openPackage
                    )
                    activitySection
                }
            }
        }
        .task {
            guard loadsAutomatically else { return }
            await model.load()
        }
        .sheet(isPresented: $model.isConsolePresented) { liveConsole }
        .sheet(isPresented: packagePreviewBinding) { packagePreviewSheet }
        .sheet(isPresented: offlineInspectionBinding) { offlineConsole }
        .confirmationDialog(
            L10n.string("observability.confirm.apply.title"),
            isPresented: $isApplyConfirmationPresented
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
            Button(L10n.string("observability.apply")) { Task { await model.applyConfiguration() } }
        } message: {
            Text(L10n.string("observability.confirm.apply.message"))
        }
        .confirmationDialog(
            L10n.string("observability.confirm.delete.title"),
            isPresented: $isDeleteConfirmationPresented
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
            Button(L10n.string("observability.clear"), role: .destructive) {
                Task { await model.deleteLocalLogs() }
            }
        } message: {
            Text(L10n.string("observability.confirm.delete.message"))
        }
        .confirmationDialog(
            L10n.string("observability.confirm.sensitiveLogging.title"),
            isPresented: $isSensitiveLoggingConfirmationPresented
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
            Button(L10n.string("observability.confirm.include")) { model.setSensitiveLoggingEnabled(true) }
        } message: {
            Text(L10n.string("observability.confirm.sensitiveLogging.message"))
        }
        .confirmationDialog(
            L10n.string("observability.confirm.sensitivePackage.title"),
            isPresented: $isSensitivePackageConfirmationPresented
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
            Button(L10n.string("observability.confirm.include")) {
                model.includeSensitiveEventsInPackage = true
            }
        } message: {
            Text(L10n.string("observability.confirm.sensitivePackage.message"))
        }
        .confirmationDialog(
            L10n.string("observability.confirm.fileNames.title"),
            isPresented: $isFileNamePackageConfirmationPresented
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
            Button(L10n.string("observability.confirm.include")) {
                model.includeFileNamesInPackage = true
            }
        } message: {
            Text(L10n.string("observability.confirm.fileNames.message"))
        }
        .confirmationDialog(
            L10n.string("observability.confirm.fullPaths.title"),
            isPresented: $isFullPathPackageConfirmationPresented
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
            Button(L10n.string("observability.confirm.include")) {
                model.includeFullPathsInPackage = true
            }
        } message: {
            Text(L10n.string("observability.confirm.fullPaths.message"))
        }
        .confirmationDialog(
            L10n.string("observability.confirm.metadataSnapshot.title"),
            isPresented: $isMetadataSnapshotConfirmationPresented
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
            Button(L10n.string("observability.confirm.include")) {
                model.includeMetadataSnapshotInPackage = true
            }
        } message: {
            Text(L10n.string("observability.confirm.metadataSnapshot.message"))
        }
        .confirmationDialog(
            L10n.string("observability.confirm.incidentDelete.title"),
            isPresented: $isIncidentDeleteConfirmationPresented
        ) {
            Button(L10n.string("settings.action.cancel"), role: .cancel) {}
            Button(L10n.string("observability.incident.delete"), role: .destructive) {
                Task { await model.deleteSelectedIncident() }
            }
        } message: {
            Text(L10n.string("observability.confirm.incidentDelete.message"))
        }
    }
}

private extension DiagnosticsSettingsPane {
    @ViewBuilder
    var feedbackBanner: some View {
        if let feedback = model.feedback {
            switch feedback {
            case let .success(message):
                SettingsStatusBanner(
                    title: localizer.resolve(message),
                    systemImage: "checkmark.circle",
                    tint: .green
                ) {}
            case let .failure(message):
                SettingsStatusBanner(
                    title: localizer.resolve(message),
                    systemImage: "exclamationmark.triangle",
                    tint: .red
                ) {}
            }
        }
    }

    var modeSection: some View {
        SettingsFormSection(title: L10n.string("observability.mode.title")) {
            Picker(L10n.string("observability.mode.title"), selection: modeBinding) {
                ForEach(AppObservabilityMode.allCases, id: \.self) { mode in
                    Text(mode.localizedLabel).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(model.configuration.mode.localizedDetail)
                .font(.callout)
                .foregroundStyle(model.configuration.mode == .developer ? Color.orange : Color.secondary)
            Picker(
                L10n.string("observability.minimumSeverity"),
                selection: $model.configuration.minimumSeverity
            ) {
                ForEach(AppObservabilitySeverity.allCases, id: \.self) { severity in
                    Text(severity.localizedLabel).tag(severity)
                }
            }
            .frame(maxWidth: 280)
            Toggle(L10n.string("observability.includeSensitive"), isOn: sensitiveLoggingBinding)
                .disabled(model.configuration.mode == .disabled)
            leaseControls
            resourceControls
            Button(L10n.string("observability.apply")) { isApplyConfirmationPresented = true }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
        }
    }

    var modeBinding: Binding<AppObservabilityMode> {
        Binding(
            get: { model.configuration.mode },
            set: model.selectMode
        )
    }

    @ViewBuilder
    var leaseControls: some View {
        if model.configuration.mode.supportsExpiry {
            Picker(L10n.string("observability.lease.policy"), selection: $model.leasePolicy) {
                ForEach(AppObservabilityExpiryPolicy.allCases, id: \.self) { policy in
                    Text(policy.localizedLabel).tag(policy)
                }
            }
            .pickerStyle(.segmented)
            if model.leasePolicy == .timed {
                Stepper(
                    L10n.format("observability.lease.duration.format", model.leaseDurationHours),
                    value: $model.leaseDurationHours,
                    in: 1 ... 168
                )
            }
            Text(model.leasePolicy.localizedDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var resourceControls: some View {
        if model.configuration.mode == .developer {
            Slider(value: developerBudgetBinding, in: 100 ... 2048, step: 100)
            Text(L10n.format("observability.budget.format", developerBudgetBinding.wrappedValue))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Stepper(
            L10n.format("observability.retention.format", model.configuration.retentionHours),
            value: $model.configuration.retentionHours,
            in: 1 ... 720
        )
    }

    var activitySection: some View {
        SettingsFormSection(title: L10n.string("observability.activity.title")) {
            HStack {
                Button {
                    model.isConsolePresented = true
                } label: {
                    Label(L10n.string("observability.openConsole"), systemImage: "waveform.path.ecg")
                }
                Button(role: .destructive) { isDeleteConfirmationPresented = true } label: {
                    Label(L10n.string("observability.clear"), systemImage: "trash")
                }
                .disabled(model.isBusy)
            }
        }
    }

    var liveConsole: some View {
        DiagnosticsConsoleView(
            events: model.events,
            catalog: model.catalog,
            onRefresh: { await model.refreshRuntimeState() },
            onMarkIncident: { await model.markIncident() }
        )
    }

    @ViewBuilder
    var packagePreviewSheet: some View {
        if let summary = model.packagePreviewSummary {
            DiagnosticsPackagePreviewSheet(
                summary: summary,
                onCancel: model.dismissPackagePreview,
                onExport: model.exportPreparedPackage
            )
        }
    }

    @ViewBuilder
    var offlineConsole: some View {
        if let inspection = model.offlineInspection {
            DiagnosticsConsoleView(
                events: inspection.events,
                catalog: model.catalog,
                packageInspection: inspection
            )
        }
    }

    var packagePreviewBinding: Binding<Bool> {
        Binding(
            get: { model.isPackagePreviewPresented },
            set: { if !$0 { model.dismissPackagePreview() } }
        )
    }

    var offlineInspectionBinding: Binding<Bool> {
        Binding(
            get: { model.offlineInspection != nil },
            set: { if !$0 { model.dismissOfflineInspection() } }
        )
    }

    var sensitiveLoggingBinding: Binding<Bool> {
        Binding(
            get: { model.configuration.includeSensitive },
            set: { isEnabled in
                if isEnabled {
                    isSensitiveLoggingConfirmationPresented = true
                } else {
                    model.setSensitiveLoggingEnabled(false)
                }
            }
        )
    }

    var sensitivePackageBinding: Binding<Bool> {
        Binding(
            get: { model.includeSensitiveEventsInPackage },
            set: { isEnabled in
                if isEnabled {
                    isSensitivePackageConfirmationPresented = true
                } else {
                    model.includeSensitiveEventsInPackage = false
                }
            }
        )
    }

    var metadataSnapshotBinding: Binding<Bool> {
        Binding(
            get: { model.includeMetadataSnapshotInPackage },
            set: { isEnabled in
                if isEnabled {
                    isMetadataSnapshotConfirmationPresented = true
                } else {
                    model.includeMetadataSnapshotInPackage = false
                }
            }
        )
    }

    var fileNamePackageBinding: Binding<Bool> {
        Binding(
            get: { model.includeFileNamesInPackage },
            set: { isEnabled in
                if isEnabled {
                    isFileNamePackageConfirmationPresented = true
                } else {
                    model.includeFileNamesInPackage = false
                    model.includeFullPathsInPackage = false
                }
            }
        )
    }

    var fullPathPackageBinding: Binding<Bool> {
        Binding(
            get: { model.includeFullPathsInPackage },
            set: { isEnabled in
                if isEnabled, model.includeFileNamesInPackage {
                    isFullPathPackageConfirmationPresented = true
                } else if !isEnabled {
                    model.includeFullPathsInPackage = false
                }
            }
        )
    }

    var developerBudgetBinding: Binding<Double> {
        Binding(
            get: { Double(model.configuration.diskBudgetBytes) / 1_048_576 },
            set: { model.configuration.diskBudgetBytes = Int64($0 * 1_048_576) }
        )
    }
}
