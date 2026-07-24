import Foundation

struct ClassifierSettingsLoadError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct ClassifierSettingsSaveError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct ClassifierSettingsPreviewError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct ClassifierSettingsFileActionError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct ClassifierSettingsValidationError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct ClassifierSettingsPendingSave: Equatable {
    var config: AppRepoConfigSnapshot
    var error: ClassifierSettingsSaveError
}

struct ClassifierSettingsDraft: Equatable {
    var enableExtensionRules: Bool
    var enableKeywordRules: Bool
    var fallbackToInbox: Bool

    init(config: AppRepoConfigSnapshot) {
        enableExtensionRules = config.enableExtensionRules
        enableKeywordRules = config.enableKeywordRules
        fallbackToInbox = config.fallbackToInbox
    }
}

extension AppRepoConfigSnapshot {
    func withClassifierRepositoryPath(_ value: String) -> AppRepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withClassifierEnableExtensionRules(_ value: Bool) -> AppRepoConfigSnapshot {
        var config = self
        config.enableExtensionRules = value
        return config
    }

    func withClassifierEnableKeywordRules(_ value: Bool) -> AppRepoConfigSnapshot {
        var config = self
        config.enableKeywordRules = value
        return config
    }

    func withClassifierFallbackToInbox(_ value: Bool) -> AppRepoConfigSnapshot {
        var config = self
        config.fallbackToInbox = value
        return config
    }
}
