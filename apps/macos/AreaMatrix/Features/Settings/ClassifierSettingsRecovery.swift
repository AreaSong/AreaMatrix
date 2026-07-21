import Foundation

struct ClassifierSettingsLoadError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsSaveError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsPreviewError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsFileActionError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsValidationError: Equatable {
    var message: String
    var recovery: String
}

struct ClassifierSettingsPendingSave: Equatable {
    var config: RepoConfigSnapshot
    var error: ClassifierSettingsSaveError
}

struct ClassifierSettingsDraft: Equatable {
    var enableExtensionRules: Bool
    var enableKeywordRules: Bool
    var fallbackToInbox: Bool

    init(config: RepoConfigSnapshot) {
        enableExtensionRules = config.enableExtensionRules
        enableKeywordRules = config.enableKeywordRules
        fallbackToInbox = config.fallbackToInbox
    }
}

protocol ClassifierRulesManaging {
    func classifierFileExists(repoPath: String) -> Bool
    func classifierCategorySlugs(repoPath: String) throws -> [String]
    func lastValidBackupExists(repoPath: String) -> Bool
    func createDefaultClassifier(repoPath: String) throws
    func storeLastValidBackup(repoPath: String) throws
    func restoreLastValidBackup(repoPath: String) throws
}

enum ClassifierRulesCategorySlugParser {
    static func slugs(in yaml: String) -> [String] {
        var seen = Set<String>()
        var slugs: [String] = []
        for line in yaml.components(separatedBy: .newlines) {
            guard let slug = slug(from: line), !seen.contains(slug) else {
                continue
            }
            seen.insert(slug)
            slugs.append(slug)
        }
        return slugs
    }

    private static func slug(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("- slug:") else { return nil }
        let value = trimmed.dropFirst("- slug:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        return unquoted.isEmpty ? nil : unquoted
    }
}

enum ClassifierRulesFileError: Error, Equatable, LocalizedError {
    case invalidRepositoryPath
    case metadataDirectoryMissing
    case classifierAlreadyExists
    case classifierMissing
    case lastValidBackupMissing

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryPath:
            "repository path is empty."
        case .metadataDirectoryMissing:
            ".areamatrix metadata directory is missing."
        case .classifierAlreadyExists:
            "classifier.yaml already exists."
        case .classifierMissing:
            "classifier.yaml is missing."
        case .lastValidBackupMissing:
            "last valid classifier backup is missing."
        }
    }
}

extension RepoConfigSnapshot {
    func withClassifierRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withClassifierEnableExtensionRules(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.enableExtensionRules = value
        return config
    }

    func withClassifierEnableKeywordRules(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.enableKeywordRules = value
        return config
    }

    func withClassifierFallbackToInbox(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.fallbackToInbox = value
        return config
    }
}
