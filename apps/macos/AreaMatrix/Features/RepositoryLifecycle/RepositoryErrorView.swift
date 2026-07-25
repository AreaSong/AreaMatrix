import SwiftUI

struct MainRepoErrorView: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let repoPath: String
    let mapping: CoreErrorMappingSnapshot?
    let validation: RepoPathValidationSnapshot?
    let isRetrying: Bool
    let retryErrorMapping: CoreErrorMappingSnapshot?
    let externalRemoval: MainRepoExternalRemovalState
    let diagnostics: MainRepoDiagnosticsState
    let lastOpenedAt: Int64?
    let onRetry: () -> Void
    let onReconnectFolder: () -> Void
    let onOpenRepair: () -> Void
    let onConfirmExternalRemoval: () -> Void
    let onRevealFolder: () -> Void
    let onRequestDiagnostics: () -> Void
    let onConfirmDiagnostics: () -> Void
    let onCancelDiagnostics: () -> Void
    let onChooseAnotherFolder: () -> Void

    init(
        repoPath: String,
        mapping: CoreErrorMappingSnapshot?,
        validation: RepoPathValidationSnapshot? = nil,
        isRetrying: Bool = false,
        retryErrorMapping: CoreErrorMappingSnapshot? = nil,
        externalRemoval: MainRepoExternalRemovalState = .unavailable,
        diagnostics: MainRepoDiagnosticsState = .idle,
        lastOpenedAt: Int64? = nil,
        onRetry: @escaping () -> Void = {},
        onReconnectFolder: @escaping () -> Void = {},
        onOpenRepair: @escaping () -> Void = {},
        onConfirmExternalRemoval: @escaping () -> Void = {},
        onRevealFolder: @escaping () -> Void = {},
        onRequestDiagnostics: @escaping () -> Void = {},
        onConfirmDiagnostics: @escaping () -> Void = {},
        onCancelDiagnostics: @escaping () -> Void = {},
        onChooseAnotherFolder: @escaping () -> Void
    ) {
        self.repoPath = repoPath
        self.mapping = mapping
        self.validation = validation
        self.isRetrying = isRetrying
        self.retryErrorMapping = retryErrorMapping
        self.externalRemoval = externalRemoval
        self.diagnostics = diagnostics
        self.lastOpenedAt = lastOpenedAt
        self.onRetry = onRetry
        self.onReconnectFolder = onReconnectFolder
        self.onOpenRepair = onOpenRepair
        self.onConfirmExternalRemoval = onConfirmExternalRemoval
        self.onRevealFolder = onRevealFolder
        self.onRequestDiagnostics = onRequestDiagnostics
        self.onConfirmDiagnostics = onConfirmDiagnostics
        self.onCancelDiagnostics = onCancelDiagnostics
        self.onChooseAnotherFolder = onChooseAnotherFolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            repositoryDetails
            diagnosticsSection
            actionRow
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(36)
        .areaMatrixGlassContentPanel(width: 700, padding: 0)
        .areaMatrixPageContentEntrance(delay: AreaMatrixMotionTokens.EntranceDelay.body)
        .accessibilityElement(children: .contain)
    }

    private var activeMapping: CoreErrorMappingSnapshot? {
        retryErrorMapping ?? mapping
    }

    private var presentation: RepositoryErrorPresentation {
        RepositoryErrorPresentation.mainRepo(mapping: activeMapping)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(localizer.resolve(presentation.title), systemImage: "exclamationmark.triangle")
                .font(.title.weight(.semibold))
                .foregroundStyle(AreaMatrixTheme.Colors.coral)
                .accessibilityAddTraits(.isHeader)
            Text(localizer.resolve(presentation.message))
                .font(.body)
                .foregroundStyle(.secondary)
            Text(L10n.string("This error does not mean your files were deleted."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var repositoryDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("Repository"))
                .font(.headline)
            AreaMatrixPathBox(
                path: repoPath,
                style: .glass,
                lineLimit: 3,
                alignment: .leading
            )
            if let activeMapping {
                Text(L10n.format("repository.error.kind", activeMapping.kind.displayName))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L10n.format("repository.error.action", activeMapping.suggestedAction))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                technicalDetails(activeMapping)
            }
            Text(lastOpenedLine)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let validation {
                Text(L10n.format(
                    "repository.lastValidationInitialized",
                    validation.isInitialized ? L10n.string("Yes") : L10n.string("No")
                ))
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            externalRemovalStatus
        }
    }

    @ViewBuilder
    private func technicalDetails(_ mapping: CoreErrorMappingSnapshot) -> some View {
        if presentation.showsTechnicalDetails {
            DisclosureGroup(L10n.string("Technical Details")) {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var externalRemovalStatus: some View {
        switch externalRemoval {
        case let .idle(path):
            Text("External removal candidate: \(path)")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .syncing(path):
            Text("Syncing external removal: \(path)")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .synced(result):
            Text(L10n.plural("repository.externalRemoval.syncedCount", count: result.detectedDeletes))
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .failed(mapping):
            Text(L10n.format("repository.externalRemoval.syncFailed", mapping.userMessage))
                .font(.callout)
                .foregroundStyle(.secondary)
        case .unavailable:
            EmptyView()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(primaryActionTitle, action: primaryAction)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(AreaMatrixPrimaryButtonStyle())
                .disabled(isRetrying)
            if case .idle = externalRemoval {
                Button(L10n.string("Confirm external removal"), action: onConfirmExternalRemoval)
                    .buttonStyle(AreaMatrixSecondaryButtonStyle())
                    .disabled(isRetrying)
            }
            Button(L10n.string("Choose another repository"), action: onChooseAnotherFolder)
                .disabled(isRetrying)
            Button(L10n.string("Export diagnostics"), action: onRequestDiagnostics)
                .disabled(isRetrying || diagnosticsIsBusy)
            if shouldShowRevealFolder {
                Button(L10n.string("Reveal last known folder"), action: onRevealFolder)
                    .disabled(isRetrying)
            }
            if isRetrying {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(L10n.string("Retrying repository validation"))
            }
        }
    }

    @ViewBuilder
    private var diagnosticsSection: some View {
        switch diagnostics {
        case .idle:
            EmptyView()
        case .confirmingPrivacy:
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("diagnostics.repositoryPrivacyDetail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(L10n.string("Create diagnostics"), action: onConfirmDiagnostics)
                        .buttonStyle(.borderedProminent)
                    Button(L10n.string("Cancel"), action: onCancelDiagnostics)
                }
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        case .collecting:
            Label(L10n.string("Preparing repository diagnostics..."), systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.string("Diagnostics collected"), systemImage: "doc.badge.gearshape")
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if !snapshot.warnings.isEmpty {
                    Text(snapshot.warnings.joined(separator: "\n"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case let .failed(mapping):
            Text(L10n.format("repository.diagnostics.failed", mapping.userMessage))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var primaryActionTitle: String {
        localizer.resolve(isRetrying ? presentation.runningActionTitle : presentation.primaryActionTitle)
    }

    private var primaryAction: () -> Void {
        switch presentation.primaryAction {
        case .openRepair:
            onOpenRepair
        case .reconnectFolder:
            onReconnectFolder
        case .retry, .downloadAndRetry:
            onRetry
        }
    }

    private var lastOpenedLine: String {
        guard let lastOpenedAt else { return L10n.string("Last opened: Not recorded") }

        let date = Date(timeIntervalSince1970: TimeInterval(lastOpenedAt))
        return L10n.format(
            "repository.lastOpened",
            date.formatted(date: .abbreviated, time: .shortened)
        )
    }

    private var shouldShowRevealFolder: Bool {
        if validation?.exists == true { return true }
        guard let kind = activeMapping?.kind else { return false }
        return kind != .fileNotFound && kind != .invalidPath
    }

    private var diagnosticsIsBusy: Bool {
        if case .collecting = diagnostics { return true }
        return false
    }
}
