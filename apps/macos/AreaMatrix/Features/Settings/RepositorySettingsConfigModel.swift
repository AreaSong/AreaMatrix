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
            "Generated only"
        case .rootAreaMatrixFile:
            "Root AREAMATRIX.md"
        }
    }
}

enum RepositorySettingsConfigLocale: String, CaseIterable, Equatable, Identifiable {
    case system
    case zhHans
    case zhCN
    case en

    var id: String {
        rawValue
    }

    init(snapshotValue: String) {
        switch snapshotValue.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "zh-Hans":
            self = .zhHans
        case "zh-CN":
            self = .zhCN
        case "en":
            self = .en
        default:
            self = .system
        }
    }

    var snapshotValue: String {
        switch self {
        case .system:
            "system"
        case .zhHans:
            "zh-Hans"
        case .zhCN:
            "zh-CN"
        case .en:
            "en"
        }
    }

    var label: String {
        snapshotValue
    }
}

struct RepositorySettingsConfigDraft: Equatable {
    var overviewOutput: RepositorySettingsConfigOverviewOutput
    var locale: RepositorySettingsConfigLocale
    var iCloudWarn: Bool
    var fallbackToInbox: Bool

    init(config: RepoConfigSnapshot) {
        overviewOutput = RepositorySettingsConfigOverviewOutput(snapshotValue: config.overviewOutput)
        locale = RepositorySettingsConfigLocale(snapshotValue: config.locale)
        iCloudWarn = config.iCloudWarn
        fallbackToInbox = config.fallbackToInbox
    }

    static var empty: RepositorySettingsConfigDraft {
        RepositorySettingsConfigDraft(
            overviewOutput: .generatedOnly,
            locale: .system,
            iCloudWarn: true,
            fallbackToInbox: true
        )
    }

    private init(
        overviewOutput: RepositorySettingsConfigOverviewOutput,
        locale: RepositorySettingsConfigLocale,
        iCloudWarn: Bool,
        fallbackToInbox: Bool
    ) {
        self.overviewOutput = overviewOutput
        self.locale = locale
        self.iCloudWarn = iCloudWarn
        self.fallbackToInbox = fallbackToInbox
    }

    func applying(to config: RepoConfigSnapshot) -> RepoConfigSnapshot {
        var updated = config
        updated.overviewOutput = overviewOutput.snapshotValue
        updated.locale = locale.snapshotValue
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
        updater: any CoreConfigurationUpdating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        accessibilityAnnouncer: any AccessibilityAnnouncing = VoiceOverAccessibilityAnnouncer()
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
            saveState = .saved("Repository settings already match Core config.")
            return true
        }

        saveState = .saving
        do {
            try await updater.updateConfig(repoPath: repoPath, newConfig: newConfig)
            saveState = .saved("Repository settings saved.")
            accessibilityAnnouncer.announce("Repository settings saved.")
            return true
        } catch {
            saveState = await .failed(configError(for: error))
            accessibilityAnnouncer.announce("Repository settings could not be saved.")
            return false
        }
    }

    private func configError(for error: Error) async -> RepositorySettingsConfigError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return RepositorySettingsConfigError(message: mapping.userMessage, recovery: mapping.suggestedAction)
        }

        return RepositorySettingsConfigError(
            message: "Repository settings could not be saved.",
            recovery: "Retry after the repository is available and writable."
        )
    }
}
