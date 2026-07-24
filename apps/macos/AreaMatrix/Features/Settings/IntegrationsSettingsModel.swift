import Combine
import Foundation

enum IntegrationsRepositoryLocation: Equatable {
    case iCloudDrive
    case localFolder
    case unknown

    var label: String {
        switch self {
        case .iCloudDrive:
            L10n.string("iCloud Drive")
        case .localFolder:
            L10n.string("Local folder")
        case .unknown:
            L10n.string("Unknown")
        }
    }
}

enum IntegrationsICloudStatus: Equatable {
    case available
    case unavailable
    case unknown

    var label: String {
        switch self {
        case .available:
            L10n.string("Available")
        case .unavailable:
            L10n.string("Unavailable")
        case .unknown:
            L10n.string("Unknown")
        }
    }

    var canRetry: Bool {
        self == .unknown
    }
}

struct IntegrationsICloudSnapshot: Equatable {
    var repositoryLocation: IntegrationsRepositoryLocation
    var iCloudStatus: IntegrationsICloudStatus
}

struct IntegrationsSettingsError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

enum IntegrationsSettingsActionFeedback: Equatable {
    case success(LocalizedMessage)
    case failed(IntegrationsSettingsError)
}

struct IntegrationsSettingsSummary: Equatable {
    var repositoryLocation: IntegrationsRepositoryLocation
    var iCloudStatus: IntegrationsICloudStatus
    var iCloudWarningsEnabled: Bool

    var shouldShowICloudRiskWarning: Bool {
        repositoryLocation == .iCloudDrive && iCloudWarningsEnabled
    }

    var canRetryStatus: Bool {
        iCloudStatus.canRetry || repositoryLocation == .unknown
    }

    func withICloudWarningsEnabled(_ enabled: Bool) -> IntegrationsSettingsSummary {
        IntegrationsSettingsSummary(
            repositoryLocation: repositoryLocation,
            iCloudStatus: iCloudStatus,
            iCloudWarningsEnabled: enabled
        )
    }
}

enum IntegrationConflictListPresentation {
    static var reviewConflictsTitle: String {
        L10n.string("Review conflicts")
    }

    static let reviewConflictsAccessibilityID = "icloud-conflicts-icloud-conflicts-core-review-conflicts"
}

protocol ICloudStatusDetecting: Sendable {
    func snapshot(repoPath: String, config: AppRepoConfigSnapshot) async -> IntegrationsICloudSnapshot
}

protocol ICloudHelpOpening: Sendable {
    @MainActor
    func openICloudHelp() throws
}

@MainActor
final class IntegrationsSettingsModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(IntegrationsSettingsError)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var summary: IntegrationsSettingsSummary?
    @Published private(set) var saveError: IntegrationsSettingsError?
    @Published private(set) var actionFeedback: IntegrationsSettingsActionFeedback?
    @Published private(set) var isSaving = false

    let repoPath: String

    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let errorMapper: any CoreErrorMapping
    private let statusDetector: any ICloudStatusDetecting
    private let finderOpener: any RepositoryFinderOpening
    private let helpOpener: any ICloudHelpOpening
    private var savedConfig: AppRepoConfigSnapshot?
    private var pendingRetry: AppRepoConfigSnapshot?

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        statusDetector: any ICloudStatusDetecting = IntegrationsSettingsPlatformServices.statusDetector,
        finderOpener: any RepositoryFinderOpening = IntegrationsSettingsPlatformServices.finderOpener,
        helpOpener: any ICloudHelpOpening = IntegrationsSettingsPlatformServices.helpOpener
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.errorMapper = errorMapper
        self.statusDetector = statusDetector
        self.finderOpener = finderOpener
        self.helpOpener = helpOpener
    }

    var isLoaded: Bool {
        loadState == .loaded
    }

    var hasRetryableSave: Bool {
        pendingRetry != nil && !isSaving
    }

    var canRetryStatus: Bool {
        summary?.canRetryStatus == true && !isSaving
    }

    func load() async {
        loadState = .loading
        saveError = nil
        actionFeedback = nil
        pendingRetry = nil

        do {
            let config = try await loader.loadConfig(repoPath: repoPath)
                .withIntegrationsRepositoryPath(repoPath)
            let status = await statusDetector.snapshot(repoPath: repoPath, config: config)
            savedConfig = config
            summary = IntegrationsSettingsSummary(
                repositoryLocation: status.repositoryLocation,
                iCloudStatus: status.iCloudStatus,
                iCloudWarningsEnabled: config.iCloudWarn
            )
            loadState = .loaded
        } catch {
            savedConfig = nil
            summary = nil
            loadState = await .failed(settingsError(for: error, fallbackRecovery: L10n.message("Retry status")))
        }
    }

    func setICloudWarningsEnabled(_ enabled: Bool) async {
        guard !isSaving, let savedConfig, enabled != summary?.iCloudWarningsEnabled else {
            return
        }

        await persist(updating: savedConfig.withIntegrationsICloudWarn(enabled))
    }

    func retrySave() async {
        guard let pendingRetry, !isSaving else {
            return
        }

        await persist(updating: pendingRetry)
    }

    func revealRepositoryInFinder() {
        actionFeedback = nil
        do {
            try finderOpener.openRepositoryInFinder(repoPath: repoPath)
            actionFeedback = .success(L10n.message("Repository folder revealed in Finder."))
        } catch {
            actionFeedback = .failed(IntegrationsSettingsError(
                message: L10n.message("Repository folder cannot be revealed."),
                recovery: L10n
                    .message("Check that the repository folder still exists and Finder has permission to open it.")
            ))
        }
    }

    func recordConflictResolveEntry(_ conflict: ICloudConflictPairSnapshot) {
        actionFeedback = .success(L10n.message(
            "settings.integrations.openSingleItemResolver",
            arguments: [.string(conflict.fileDisplayName)]
        ))
    }

    func recordConflictDiagnosticsEntry() {
        actionFeedback = .success(L10n.message("Diagnostics can be collected from the conflict list error state."))
    }

    func openICloudHelp() {
        actionFeedback = nil
        do {
            try helpOpener.openICloudHelp()
            actionFeedback = .success(L10n.message("iCloud help opened."))
        } catch {
            actionFeedback = .failed(IntegrationsSettingsError(
                message: L10n.message("iCloud help cannot be opened."),
                recovery: L10n.message("Check the default browser or open Apple iCloud Drive help manually.")
            ))
        }
    }

    private func persist(updating config: AppRepoConfigSnapshot) async {
        guard let savedConfig else { return }
        isSaving = true
        saveError = nil
        actionFeedback = nil
        do {
            let updated = try await updater.updateConfig(repoPath: repoPath, from: savedConfig, to: config)
            self.savedConfig = updated
            summary = summary?.withICloudWarningsEnabled(updated.iCloudWarn)
            pendingRetry = nil
        } catch {
            summary = summary?.withICloudWarningsEnabled(savedConfig.iCloudWarn)
            let mappedError = await settingsError(for: error, fallbackRecovery: L10n.message("Retry save"))
            saveError = mappedError
            pendingRetry = config
        }
        isSaving = false
    }

    private func settingsError(
        for error: Error,
        fallbackRecovery: LocalizedMessage
    ) async -> IntegrationsSettingsError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return IntegrationsSettingsError(
                message: mapping.userMessageDescriptor,
                recovery: mapping.recoveryMessage(fallback: fallbackRecovery)
            )
        }

        return IntegrationsSettingsError(
            message: L10n.message(
                "Unable to load integrations",
                technicalDetail: error.localizedDescription
            ),
            recovery: fallbackRecovery
        )
    }
}

extension AppRepoConfigSnapshot {
    func withIntegrationsRepositoryPath(_ value: String) -> AppRepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withIntegrationsICloudWarn(_ value: Bool) -> AppRepoConfigSnapshot {
        var config = self
        config.iCloudWarn = value
        return config
    }
}
