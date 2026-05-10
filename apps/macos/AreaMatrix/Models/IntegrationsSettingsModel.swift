import AppKit
import Combine
import Foundation

enum IntegrationsRepositoryLocation: Equatable {
    case iCloudDrive
    case localFolder
    case unknown

    var label: String {
        switch self {
        case .iCloudDrive:
            "iCloud Drive"
        case .localFolder:
            "Local folder"
        case .unknown:
            "Unknown"
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
            "Available"
        case .unavailable:
            "Unavailable"
        case .unknown:
            "Unknown"
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
    var message: String
    var recovery: String
}

enum IntegrationsSettingsActionFeedback: Equatable {
    case success(String)
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
    static let reviewConflictsTitle = "Review conflicts"
    static let reviewConflictsAccessibilityID = "S1-36-C1-25-review-conflicts"
}

protocol ICloudStatusDetecting: Sendable {
    func snapshot(repoPath: String, config: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot
}

protocol ICloudHelpOpening: Sendable {
    @MainActor
    func openICloudHelp() throws
}

struct LocalICloudStatusDetector: ICloudStatusDetecting {
    func snapshot(repoPath: String, config: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        let effectivePath = config.repoPath.isEmpty ? repoPath : config.repoPath
        let url = URL(fileURLWithPath: effectivePath, isDirectory: true)

        do {
            let values = try url.resourceValues(forKeys: [.isUbiquitousItemKey])
            guard let isUbiquitous = values.isUbiquitousItem else {
                return IntegrationsICloudSnapshot(repositoryLocation: .unknown, iCloudStatus: .unknown)
            }

            if !isUbiquitous {
                return IntegrationsICloudSnapshot(repositoryLocation: .localFolder, iCloudStatus: .unavailable)
            }

            let status: IntegrationsICloudStatus = FileManager.default.ubiquityIdentityToken == nil
                ? .unavailable
                : .available
            return IntegrationsICloudSnapshot(repositoryLocation: .iCloudDrive, iCloudStatus: status)
        } catch {
            return IntegrationsICloudSnapshot(repositoryLocation: .unknown, iCloudStatus: .unknown)
        }
    }
}

enum ICloudHelpOpenError: Error, Equatable, LocalizedError {
    case helpURLUnavailable
    case openRejected

    var errorDescription: String? {
        switch self {
        case .helpURLUnavailable:
            "iCloud help URL is unavailable."
        case .openRejected:
            "iCloud help could not be opened."
        }
    }
}

struct NSWorkspaceICloudHelpOpener: ICloudHelpOpening {
    @MainActor
    func openICloudHelp() throws {
        guard let url = URL(string: "https://support.apple.com/guide/mac-help/use-icloud-drive-mchl1a02d711/mac")
        else {
            throw ICloudHelpOpenError.helpURLUnavailable
        }

        guard NSWorkspace.shared.open(url) else {
            throw ICloudHelpOpenError.openRejected
        }
    }
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
    private var savedConfig: RepoConfigSnapshot?
    private var pendingRetry: RepoConfigSnapshot?

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = CoreBridge(),
        updater: any CoreConfigurationUpdating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        statusDetector: any ICloudStatusDetecting = LocalICloudStatusDetector(),
        finderOpener: any RepositoryFinderOpening = NSWorkspaceRepositoryFinderOpener(),
        helpOpener: any ICloudHelpOpening = NSWorkspaceICloudHelpOpener()
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
            loadState = await .failed(settingsError(for: error, fallbackRecovery: "Retry status"))
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
            actionFeedback = .success("Repository folder revealed in Finder.")
        } catch {
            actionFeedback = .failed(IntegrationsSettingsError(
                message: "Repository folder cannot be revealed.",
                recovery: "Check that the repository folder still exists and Finder has permission to open it."
            ))
        }
    }

    func recordConflictResolveEntry(_ conflict: ICloudConflictPairSnapshot) {
        actionFeedback = .success("Open the single-item resolver for \(conflict.fileDisplayName).")
    }

    func recordConflictDiagnosticsEntry() {
        actionFeedback = .success("Diagnostics can be collected from the conflict list error state.")
    }

    func openICloudHelp() {
        actionFeedback = nil
        do {
            try helpOpener.openICloudHelp()
            actionFeedback = .success("iCloud help opened.")
        } catch {
            actionFeedback = .failed(IntegrationsSettingsError(
                message: "iCloud help cannot be opened.",
                recovery: "Check the default browser or open Apple iCloud Drive help manually."
            ))
        }
    }

    private func persist(updating config: RepoConfigSnapshot) async {
        isSaving = true
        saveError = nil
        actionFeedback = nil
        do {
            try await updater.updateConfig(repoPath: repoPath, newConfig: config)
            savedConfig = config
            summary = summary?.withICloudWarningsEnabled(config.iCloudWarn)
            pendingRetry = nil
        } catch {
            if let savedConfig {
                summary = summary?.withICloudWarningsEnabled(savedConfig.iCloudWarn)
            }
            let mappedError = await settingsError(for: error, fallbackRecovery: "Retry save")
            saveError = mappedError
            pendingRetry = config
        }
        isSaving = false
    }

    private func settingsError(for error: Error, fallbackRecovery: String) async -> IntegrationsSettingsError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return IntegrationsSettingsError(
                message: mapping.userMessage,
                recovery: mapping.suggestedAction.isEmpty ? fallbackRecovery : mapping.suggestedAction
            )
        }

        return IntegrationsSettingsError(
            message: error.localizedDescription,
            recovery: fallbackRecovery
        )
    }
}

extension RepoConfigSnapshot {
    func withIntegrationsRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withIntegrationsICloudWarn(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.iCloudWarn = value
        return config
    }
}
