import SwiftUI

struct DBRepairConfirmView: View {
    @EnvironmentObject private var localizer: AppLocalizer
    @StateObject private var model: DatabaseRepairConfirmModel

    private let onCancel: () -> Void
    private let onRepairSucceeded: () async -> Void
    private let onOpenRepositoryInFinder: () -> Void

    init(
        repoPath: String,
        scanSession: ScanSessionSnapshot?,
        mapping: CoreErrorMappingSnapshot?,
        lastOpenedAt: Int64? = nil,
        metadataRepairer: any CoreMetadataRepairing,
        repositoryReindexer: any CoreRepositoryReindexing,
        startupRecoverer: any CoreStartupRecovering,
        repositoryWriteCoordinator: RepositoryWriteCoordinator,
        diagnosticsCollector: any CoreDiagnosticsCollecting,
        errorMapper: any CoreErrorMapping,
        onCancel: @escaping () -> Void,
        onRepairSucceeded: @escaping () async -> Void,
        onOpenRepositoryInFinder: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: DatabaseRepairConfirmModel(
            repoPath: repoPath,
            scanSession: scanSession,
            mapping: mapping,
            lastOpenedAt: lastOpenedAt,
            metadataRepairer: metadataRepairer,
            repositoryReindexer: repositoryReindexer,
            startupRecoverer: startupRecoverer,
            repositoryWriteCoordinator: repositoryWriteCoordinator,
            diagnosticsCollector: diagnosticsCollector,
            errorMapper: errorMapper
        ))
        self.onCancel = onCancel
        self.onRepairSucceeded = onRepairSucceeded
        self.onOpenRepositoryInFinder = onOpenRepositoryInFinder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    repositoryContext
                    startupRecoveryStatus
                    preflightStatus
                    metadataRepairPlan
                    diagnosticsStatus
                    repairStatus
                    rescanPlan
                }
                .frame(maxWidth: 720, alignment: .leading)
            }
            footer
        }
        .padding(36)
        .areaMatrixGlassContentPanel(width: 780, padding: 0)
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
        .confirmationDialog("Export diagnostics?", isPresented: diagnosticsConfirmationBinding) {
            Button(L10n.string("Cancel"), role: .cancel, action: model.cancelDiagnosticsExport)
            Button(L10n.string("Export diagnostics")) {
                Task { await model.collectDiagnostics() }
            }
        } message: {
            Text(L10n.string("diagnostics.repositoryPrivacyDetail"))
        }
        .task {
            async let startup: Void = model.runStartupRecoveryCheckIfNeeded()
            async let preflight: Void = model.loadRepairPreflightIfNeeded()
            _ = await (startup, preflight)
        }
        .onDisappear(perform: model.cancelDiagnosticsExport)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("database-repair-db-repair-confirm")
    }
}

private extension DBRepairConfirmView {
    private var header: some View {
        AreaMatrixStepHeader(
            systemImage: "wrench.and.screwdriver",
            tint: AreaMatrixTheme.Colors.gold,
            title: L10n.string("Repair Repository Metadata?"),
            subtitle: L10n.string(
                "AreaMatrix cannot read the repository metadata database. Your files remain in the repository folder."
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var repositoryContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Repository")).font(.headline)
            AreaMatrixPathBox(path: model.repoPath, style: .glass, lineLimit: 3, alignment: .leading)
            if let mapping = model.initialMapping {
                Text(L10n.format("onboarding.databaseRepair.errorKind", mapping.kind.displayName))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(mapping.userMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                DisclosureGroup(L10n.string("Technical Details")) {
                    Text(mapping.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.callout)
            }
            Text(lastOpenedLine)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var startupRecoveryStatus: some View {
        StartupRecoveryCheckStatusView(
            state: model.startupRecoveryState,
            onRetry: { Task { await model.retryStartupRecovery() } }
        )
    }

    @ViewBuilder
    private var preflightStatus: some View {
        switch model.preflightState {
        case .idle, .loading:
            Label(L10n.string("Inspecting metadata..."), systemImage: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .ready(preflight):
            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.string("Metadata inspection complete"), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text(L10n.format("metadataRepair.preflight.state", preflight.localeState.rawValue))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let unsupported = preflight.unsupportedLocale {
                    Text(L10n.format("metadataRepair.preflight.unsupportedLocale", unsupported))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if preflight.requiresExplicitLocaleSelection {
                    Picker(L10n.string("Repository content language"), selection: $model.selectedRecoveryLanguage) {
                        Text(L10n.string("Choose a language")).tag(RepositoryContentLanguage?.none)
                        ForEach(RepositoryContentLanguage.allCases) { language in
                            Text(localizer.resolve(language.displayMessage)).tag(Optional(language))
                        }
                    }
                    .accessibilityIdentifier("database-repair-content-language")
                } else if let policy = preflight.repositoryLocalePolicy {
                    Text(L10n.format("metadataRepair.preflight.preservedLocale", policy))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        case let .failed(mapping):
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("Metadata inspection failed"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(mapping.userMessage).font(.callout)
                Button(L10n.string("Retry inspection")) { Task { await model.retryRepairPreflight() } }
            }
        }
    }

    private var metadataRepairPlan: some View {
        VStack(alignment: .leading, spacing: 16) {
            RepairChecklistSection(
                title: L10n.string("Metadata repair will"),
                systemImage: "wrench.and.screwdriver",
                items: [
                    L10n.string("Preserve the current AreaMatrix metadata state for diagnostics."),
                    L10n.string("Verify, initialize, or rebuild AreaMatrix metadata only.")
                ]
            )
            RepairChecklistSection(
                title: L10n.string("Metadata repair will not"),
                systemImage: "checkmark.shield",
                items: [
                    L10n.string("Scan or index repository files."),
                    L10n.string("Generate or rewrite overviews."),
                    L10n.string("Move, rename, delete, or overwrite user files.")
                ]
            )
            Toggle(
                L10n.string("I understand that repair changes AreaMatrix metadata only."),
                isOn: $model.isMetadataSafetyConfirmed
            )
            .toggleStyle(.checkbox)
            .disabled(model.repairState.isRunning)
            .accessibilityIdentifier("database-repair-confirm-metadata-only")
        }
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch model.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label(L10n.string("Preparing repository diagnostics..."), systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.string("Diagnostics collected"), systemImage: "doc.badge.gearshape")
                    .foregroundStyle(.green)
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        case let .failed(mapping):
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.string("Diagnostics could not be created"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(mapping.userMessage).font(.callout)
            }
        }
    }

    @ViewBuilder
    private var repairStatus: some View {
        switch model.repairState {
        case .idle:
            EmptyView()
        case let .running(step):
            RepairProgressView(currentStep: step)
        case let .succeeded(report):
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("Metadata repair completed"), systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text(report.summaryText).font(.callout)
                if let path = report.diagnosticsSnapshotPath {
                    Text(L10n.format("metadataRepair.diagnosticsPath", path))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        case let .failed(mapping):
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.string("Metadata repair failed"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(mapping.userMessage).font(.callout)
                Text(mapping.suggestedAction)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var rescanPlan: some View {
        if model.repairState.isSucceeded {
            VStack(alignment: .leading, spacing: 12) {
                Divider()
                Text(L10n.string("Rescan Repository Files")).font(.headline)
                Text(L10n.string("metadataRepair.rescanLimitations"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle(L10n.string("I want to scan the repository now."), isOn: $model.isRescanConfirmed)
                    .toggleStyle(.checkbox)
                    .disabled(model.rescanState.isRunning)
                    .accessibilityIdentifier("database-repair-confirm-rescan")
                rescanStatus
            }
        }
    }

    @ViewBuilder
    private var rescanStatus: some View {
        switch model.rescanState {
        case .idle:
            EmptyView()
        case .running:
            Label(L10n.string("Scanning files..."), systemImage: "arrow.clockwise")
                .foregroundStyle(.secondary)
        case let .succeeded(report):
            Label(
                L10n.format("metadataRepair.rescan.completed", report.inserted, report.updated, report.skipped),
                systemImage: "checkmark.circle"
            )
            .foregroundStyle(.green)
        case let .failed(mapping):
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.string("Rescan failed"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(mapping.userMessage).font(.callout)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L10n.string("Cancel"), action: onCancel)
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
                .disabled(model.repairState.isRunning || model.rescanState.isRunning)
            Button(L10n.string("Export diagnostics..."), action: model.requestDiagnosticsExport)
                .buttonStyle(AreaMatrixSecondaryButtonStyle())
                .disabled(!model.canExportDiagnostics)
            if model.repairState.failure != nil {
                Button(L10n.string("Open repository in Finder"), action: onOpenRepositoryInFinder)
                    .buttonStyle(AreaMatrixSecondaryButtonStyle())
            }
            Spacer()
            if model.repairState.isSucceeded {
                Button(model.rescanButtonTitle) {
                    Task {
                        await model.runRescan()
                        if model.rescanState.isSucceeded { await onRepairSucceeded() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AreaMatrixPrimaryButtonStyle(accent: AreaMatrixTheme.Colors.gold))
                .disabled(!model.canRunRescan)
                .accessibilityIdentifier("database-repair-run-rescan")
            } else {
                Button(model.primaryButtonTitle) { Task { await model.runMetadataRepair() } }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(AreaMatrixPrimaryButtonStyle(accent: AreaMatrixTheme.Colors.gold))
                    .disabled(!model.canRunMetadataRepair)
                    .accessibilityIdentifier("database-repair-run-metadata-repair")
            }
        }
        .frame(maxWidth: 720)
        .padding(.top, 18)
    }

    private var diagnosticsConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirmingPrivacy = model.diagnosticsState { return true }
                return false
            },
            set: { if !$0 { model.cancelDiagnosticsExport() } }
        )
    }

    private var lastOpenedLine: String {
        guard let lastOpenedAt = model.lastOpenedAt else {
            return L10n.string("Last successful open: Not recorded")
        }
        let date = Date(timeIntervalSince1970: TimeInterval(lastOpenedAt))
        return L10n.format(
            "onboarding.databaseRepair.lastSuccessfulOpen",
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }
}
