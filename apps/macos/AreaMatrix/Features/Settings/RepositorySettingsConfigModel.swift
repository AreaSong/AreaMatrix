import Combine
import Foundation

enum RepositorySettingsConfigOverviewOutput: String, CaseIterable, Equatable, Identifiable {
    case generatedOnly
    case rootAreaMatrixFile

    var id: String {
        rawValue
    }

    init(snapshotValue: String) {
        self = snapshotValue == "RootAreaMatrixFile" ? .rootAreaMatrixFile : .generatedOnly
    }

    var snapshotValue: String {
        switch self {
        case .generatedOnly:
            "GeneratedOnly"
        case .rootAreaMatrixFile:
            "RootAreaMatrixFile"
        }
    }

    var label: String {
        switch self {
        case .generatedOnly:
            L10n.string("Generated only")
        case .rootAreaMatrixFile:
            L10n.string("Root AREAMATRIX.md")
        }
    }
}

struct RepositorySettingsConfigDraft: Equatable {
    var overviewOutput: RepositorySettingsConfigOverviewOutput
    var contentLanguage: RepositoryContentLanguage
    var iCloudWarn: Bool
    var fallbackToInbox: Bool

    init(config: RepoConfigSnapshot) {
        overviewOutput = RepositorySettingsConfigOverviewOutput(snapshotValue: config.overviewOutput)
        contentLanguage = RepositoryContentLanguage(snapshotValue: config.locale)
        iCloudWarn = config.iCloudWarn
        fallbackToInbox = config.fallbackToInbox
    }

    static var empty: RepositorySettingsConfigDraft {
        RepositorySettingsConfigDraft(
            overviewOutput: .generatedOnly,
            contentLanguage: .followInterface,
            iCloudWarn: true,
            fallbackToInbox: true
        )
    }

    private init(
        overviewOutput: RepositorySettingsConfigOverviewOutput,
        contentLanguage: RepositoryContentLanguage,
        iCloudWarn: Bool,
        fallbackToInbox: Bool
    ) {
        self.overviewOutput = overviewOutput
        self.contentLanguage = contentLanguage
        self.iCloudWarn = iCloudWarn
        self.fallbackToInbox = fallbackToInbox
    }

    func applying(to config: RepoConfigSnapshot) -> RepoConfigSnapshot {
        var updated = config
        updated.overviewOutput = overviewOutput.snapshotValue
        updated.locale = contentLanguage.snapshotValue
        updated.iCloudWarn = iCloudWarn
        updated.fallbackToInbox = fallbackToInbox
        return updated
    }
}

struct RepositorySettingsConfigError: Equatable {
    var message: String
    var recovery: String
}

enum RepositorySettingsConfigSaveState: Equatable {
    case idle
    case saving
    case saved(String)
    case failed(RepositorySettingsConfigError)

    var isSaving: Bool {
        if case .saving = self {
            return true
        }
        return false
    }
}

@MainActor
final class RepositorySettingsConfigModel: ObservableObject {
    @Published private(set) var saveState: RepositorySettingsConfigSaveState = .idle

    let repoPath: String
    private let updater: any CoreConfigurationUpdating
    private let errorMapper: any CoreErrorMapping
    private let accessibilityAnnouncer: any AccessibilityAnnouncing

    init(
        repoPath: String,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        accessibilityAnnouncer: any AccessibilityAnnouncing = RepositorySettingsPlatformServices.accessibilityAnnouncer
    ) {
        self.repoPath = repoPath
        self.updater = updater
        self.errorMapper = errorMapper
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    func resetFeedback() {
        guard !saveState.isSaving else { return }
        saveState = .idle
    }

    func save(draft: RepositorySettingsConfigDraft, currentConfig: RepoConfigSnapshot) async -> Bool {
        guard !saveState.isSaving else { return false }
        let newConfig = draft.applying(to: currentConfig)
        guard newConfig != currentConfig else {
            saveState = .saved(L10n.string("Repository settings already match Core config."))
            return true
        }

        saveState = .saving
        do {
            try await updater.updateConfig(repoPath: repoPath, newConfig: newConfig)
            saveState = .saved(L10n.string("Repository settings saved."))
            accessibilityAnnouncer.announce(L10n.string("Repository settings saved."))
            return true
        } catch {
            saveState = await .failed(configError(for: error))
            accessibilityAnnouncer.announce(L10n.string("Repository settings could not be saved."))
            return false
        }
    }

    private func configError(for error: Error) async -> RepositorySettingsConfigError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return RepositorySettingsConfigError(message: mapping.userMessage, recovery: mapping.suggestedAction)
        }

        return RepositorySettingsConfigError(
            message: L10n.string("Repository settings could not be saved."),
            recovery: L10n.string("Retry after the repository is available and writable.")
        )
    }
}
