import SwiftUI

struct MainListErrorRecoveryActions {
    let retryFallback: () -> Void
    let collectFallbackDiagnostics: () async -> Void
    let openRepair: () -> Void
    let openRepairWithMapping: (CoreErrorMappingSnapshot?) -> Void
    let downloadExternalSyncPlaceholder: (String) async throws -> Void

    init(
        retryFallback: @escaping () -> Void,
        collectFallbackDiagnostics: @escaping () async -> Void,
        openRepair: @escaping () -> Void = {},
        openRepairWithMapping: ((CoreErrorMappingSnapshot?) -> Void)? = nil,
        downloadExternalSyncPlaceholder: @escaping (String) async throws -> Void = { _ in }
    ) {
        self.retryFallback = retryFallback
        self.collectFallbackDiagnostics = collectFallbackDiagnostics
        self.openRepair = openRepair
        self.openRepairWithMapping = openRepairWithMapping ?? { _ in openRepair() }
        self.downloadExternalSyncPlaceholder = downloadExternalSyncPlaceholder
    }

    static let none = MainListErrorRecoveryActions(
        retryFallback: {},
        collectFallbackDiagnostics: {}
    )
}

@MainActor
struct MainExternalSyncErrorBanner: View {
    let error: CoreErrorMappingSnapshot
    let fileListModel: MainFileListModel
    let recoveryActions: MainListErrorRecoveryActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("External changes are paused", systemImage: "exclamationmark.triangle")
                .font(.headline)
            if let relativePath = fileListModel.failedExternalSyncRelativePath {
                Text(relativePath)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            Text(error.userMessage)
            Text(error.suggestedAction)
                .foregroundStyle(.secondary)
            recoveryButtons
            recoveryStatus
            diagnosticsStatus
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("external-sync-error-banner")
    }

    private var recoveryButtons: some View {
        HStack {
            if fileListModel.canDownloadExternalSyncPlaceholder {
                Button("Download & Retry") {
                    Task {
                        await fileListModel.downloadExternalSyncPlaceholder(
                            using: recoveryActions.downloadExternalSyncPlaceholder
                        )
                    }
                }
                .disabled(fileListModel.isExternalSyncPlaceholderDownloading)
                .accessibilityIdentifier("external-sync-download-retry")
            }
            Button("Retry", action: fileListModel.retryExternalSync)
                .disabled(fileListModel.isExternalSyncPlaceholderDownloading)
                .accessibilityIdentifier("external-sync-global-retry")
            if canOfferRepair {
                Button("Open Repair...") { recoveryActions.openRepairWithMapping(error) }
                    .accessibilityIdentifier("external-sync-open-repair")
            }
            Button("Collect Diagnostics...") {
                fileListModel.requestCurrentListDiagnostics()
            }
            .disabled(isCollectingDiagnostics)
            .accessibilityIdentifier("external-sync-collect-diagnostics")
            DisclosureGroup("Technical Details") {
                Text(error.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var canOfferRepair: Bool {
        [.db, .config, .conflict, .repoNotInitialized, .stagingRecoveryRequired].contains(error.kind)
    }

    private var isCollectingDiagnostics: Bool {
        if case .collecting = fileListModel.diagnosticsState { return true }
        return false
    }

    @ViewBuilder
    private var recoveryStatus: some View {
        if fileListModel.isExternalSyncPlaceholderDownloading {
            Label("Requesting iCloud download...", systemImage: "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
        } else if let message = fileListModel.externalSyncRecoveryMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch fileListModel.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label("Preparing diagnostics...", systemImage: "arrow.clockwise")
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            Label("Diagnostics collected at \(snapshot.snapshotPath)", systemImage: "doc.badge.gearshape")
                .textSelection(.enabled)
        case let .failed(mapping):
            Label(mapping.userMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct MainCurrentListErrorPane: View {
    let error: CoreErrorMappingSnapshot
    let state: MainRepositoryContentState
    let fileListModel: MainFileListModel
    let recoveryActions: MainListErrorRecoveryActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Current list cannot be loaded", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(error.userMessage)
                .foregroundStyle(.secondary)
            Text(error.suggestedAction)
                .font(.callout)
                .foregroundStyle(.secondary)
            actions
            diagnosticsStatus
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var actions: some View {
        HStack {
            Button("Retry", action: retry)
            Button("Collect Diagnostics...") {
                fileListModel.requestCurrentListDiagnostics()
            }
            .disabled(isCollectingDiagnostics)
            DisclosureGroup("Technical Details") {
                Text(error.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private var isCollectingDiagnostics: Bool {
        if case .collecting = fileListModel.diagnosticsState {
            return true
        }
        return false
    }

    @ViewBuilder
    private var diagnosticsStatus: some View {
        switch fileListModel.diagnosticsState {
        case .idle, .confirmingPrivacy:
            EmptyView()
        case .collecting:
            Label("Preparing diagnostics...", systemImage: "arrow.clockwise")
                .font(.callout)
                .foregroundStyle(.secondary)
        case let .collected(snapshot):
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics collected", systemImage: "doc.badge.gearshape")
                Text(snapshot.snapshotPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .font(.callout)
        case let .failed(mapping):
            VStack(alignment: .leading, spacing: 4) {
                Label("Diagnostics could not be collected", systemImage: "exclamationmark.triangle")
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private func retry() {
        if state == .list {
            if fileListModel.hasRetryableExternalSyncFailure {
                fileListModel.retryExternalSync()
            } else {
                Task { await fileListModel.retryCurrentCategory() }
            }
        } else {
            recoveryActions.retryFallback()
        }
    }
}

extension MainRepositoryContentView {
    @ViewBuilder
    var externalSyncErrorBanner: some View {
        if let error = fileListModel.externalSyncErrorMapping {
            MainExternalSyncErrorBanner(
                error: error,
                fileListModel: fileListModel,
                recoveryActions: mainListErrorRecoveryActions
            )
        }
    }

    func currentListErrorPane(_ error: CoreErrorMappingSnapshot) -> some View {
        MainCurrentListErrorPane(
            error: error,
            state: state,
            fileListModel: fileListModel,
            recoveryActions: mainListErrorRecoveryActions
        )
    }
}
