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

    init(config: AppRepoConfigSnapshot) {
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

    func dirtyFields(comparedTo config: AppRepoConfigSnapshot) -> Set<RepositorySettingsConfigField> {
        var fields = Set<RepositorySettingsConfigField>()
        if overviewOutput.snapshotValue != config.overviewOutput { fields.insert(.overviewOutput) }
        if contentLanguage.snapshotValue != config.locale { fields.insert(.contentLanguage) }
        if iCloudWarn != config.iCloudWarn { fields.insert(.iCloudWarn) }
        if fallbackToInbox != config.fallbackToInbox { fields.insert(.fallbackToInbox) }
        return fields
    }

    func applying(
        fields: Set<RepositorySettingsConfigField>,
        to config: AppRepoConfigSnapshot
    ) -> AppRepoConfigSnapshot {
        var updated = config
        if fields.contains(.overviewOutput) { updated.overviewOutput = overviewOutput.snapshotValue }
        if fields.contains(.contentLanguage) { updated.locale = contentLanguage.snapshotValue }
        if fields.contains(.iCloudWarn) { updated.iCloudWarn = iCloudWarn }
        if fields.contains(.fallbackToInbox) { updated.fallbackToInbox = fallbackToInbox }
        return updated
    }

    func rebased(
        onto config: AppRepoConfigSnapshot,
        preserving fields: Set<RepositorySettingsConfigField>
    ) -> RepositorySettingsConfigDraft {
        var result = RepositorySettingsConfigDraft(config: config)
        if fields.contains(.overviewOutput) { result.overviewOutput = overviewOutput }
        if fields.contains(.contentLanguage) { result.contentLanguage = contentLanguage }
        if fields.contains(.iCloudWarn) { result.iCloudWarn = iCloudWarn }
        if fields.contains(.fallbackToInbox) { result.fallbackToInbox = fallbackToInbox }
        return result
    }
}

enum RepositorySettingsConfigField: String, CaseIterable, Equatable, Hashable, Identifiable {
    case overviewOutput
    case contentLanguage
    case iCloudWarn
    case fallbackToInbox

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .overviewOutput: L10n.string("Overview output")
        case .contentLanguage: L10n.string("settings.language.content.title")
        case .iCloudWarn: L10n.string("Show cloud location warnings")
        case .fallbackToInbox: L10n.string("Fallback uncategorized files to inbox")
        }
    }

    func value(in config: AppRepoConfigSnapshot) -> String {
        switch self {
        case .overviewOutput:
            RepositorySettingsConfigOverviewOutput(snapshotValue: config.overviewOutput).label
        case .contentLanguage:
            L10n.resolve(RepositoryContentLanguage(snapshotValue: config.locale).displayMessage)
        case .iCloudWarn:
            enabledLabel(config.iCloudWarn)
        case .fallbackToInbox:
            enabledLabel(config.fallbackToInbox)
        }
    }

    func value(in draft: RepositorySettingsConfigDraft) -> String {
        switch self {
        case .overviewOutput: draft.overviewOutput.label
        case .contentLanguage: L10n.resolve(draft.contentLanguage.displayMessage)
        case .iCloudWarn: enabledLabel(draft.iCloudWarn)
        case .fallbackToInbox: enabledLabel(draft.fallbackToInbox)
        }
    }

    private func enabledLabel(_ enabled: Bool) -> String {
        if enabled {
            return L10n.string("Enabled")
        }
        return L10n.string("Disabled")
    }
}

struct RepositorySettingsConfigError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

enum RepositorySettingsConfigSaveState: Equatable {
    case idle
    case saving
    case saved(LocalizedMessage)
    case conflict(RepositorySettingsConfigConflict)
    case failed(RepositorySettingsConfigError)

    var isSaving: Bool {
        if case .saving = self {
            return true
        }
        return false
    }
}

struct RepositorySettingsConfigConflict: Equatable {
    var resource: String
    var expectedRevision: Int64
    var currentRevision: Int64
    var saved: AppRepoConfigSnapshot
    var latest: AppRepoConfigSnapshot
    var local: RepositorySettingsConfigDraft
    var dirtyFields: Set<RepositorySettingsConfigField>
}

@MainActor
final class RepositorySettingsConfigModel: ObservableObject {
    @Published private(set) var saveState: RepositorySettingsConfigSaveState = .idle
    @Published private(set) var lastSavedConfig: AppRepoConfigSnapshot?

    let repoPath: String
    private let loader: any CoreConfigurationLoading
    private let updater: any CoreConfigurationUpdating
    private let errorMapper: any CoreErrorMapping
    private let accessibilityAnnouncer: any AccessibilityAnnouncing

    init(
        repoPath: String,
        loader: any CoreConfigurationLoading = AppCoreServices.configurationLoader,
        updater: any CoreConfigurationUpdating = AppCoreServices.configurationUpdater,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper,
        accessibilityAnnouncer: any AccessibilityAnnouncing = RepositorySettingsPlatformServices.accessibilityAnnouncer
    ) {
        self.repoPath = repoPath
        self.loader = loader
        self.updater = updater
        self.errorMapper = errorMapper
        self.accessibilityAnnouncer = accessibilityAnnouncer
    }

    func resetFeedback() {
        guard !saveState.isSaving else { return }
        saveState = .idle
    }

    func save(
        draft: RepositorySettingsConfigDraft,
        currentConfig: AppRepoConfigSnapshot,
        dirtyFields: Set<RepositorySettingsConfigField>
    ) async -> Bool {
        guard !saveState.isSaving else { return false }
        let newConfig = draft.applying(fields: dirtyFields, to: currentConfig)
        guard !dirtyFields.isEmpty, newConfig != currentConfig else {
            saveState = .saved(L10n.message("Repository settings already match Core config."))
            return true
        }

        saveState = .saving
        do {
            let savedConfig = try await updater.updateConfig(repoPath: repoPath, from: currentConfig, to: newConfig)
            lastSavedConfig = savedConfig
            let savedMessage = L10n.message("Repository settings saved.")
            saveState = .saved(savedMessage)
            accessibilityAnnouncer.announce(savedMessage)
            return true
        } catch {
            lastSavedConfig = nil
            if let revisionConflict = CoreRevisionConflictSnapshot(error),
               let latest = try? await loader.loadConfig(repoPath: repoPath) {
                saveState = .conflict(RepositorySettingsConfigConflict(
                    resource: revisionConflict.resource,
                    expectedRevision: revisionConflict.expectedRevision,
                    currentRevision: revisionConflict.currentRevision,
                    saved: currentConfig,
                    latest: latest,
                    local: draft,
                    dirtyFields: dirtyFields
                ))
                accessibilityAnnouncer.announce(L10n.message("settings.repository.conflict.title"))
                return false
            }
            saveState = await .failed(configError(for: error))
            accessibilityAnnouncer.announce(L10n.message("Repository settings could not be saved."))
            return false
        }
    }

    private func configError(for error: Error) async -> RepositorySettingsConfigError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return RepositorySettingsConfigError(
                message: mapping.userMessageDescriptor,
                recovery: mapping.recoveryMessage(fallback: mapping.userMessageDescriptor)
            )
        }

        return RepositorySettingsConfigError(
            message: L10n.message(
                "Repository settings could not be saved.",
                technicalDetail: error.localizedDescription
            ),
            recovery: L10n.message("Retry after the repository is available and writable.")
        )
    }
}
