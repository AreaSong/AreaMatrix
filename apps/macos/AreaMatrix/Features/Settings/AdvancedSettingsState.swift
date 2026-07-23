import Foundation

enum AdvancedSettingsOverviewOutput: String, CaseIterable, Equatable, Identifiable {
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

enum AdvancedSettingsSaveKind: Equatable {
    case overview
    case replace

    var message: LocalizedMessage {
        switch self {
        case .overview:
            L10n.message("Could not save overview setting")
        case .replace:
            L10n.message("Could not save advanced setting")
        }
    }
}

struct AdvancedSettingsError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

enum AdvancedSettingsAccessibilityID {
    static let overviewOutput = "advanced-settings-overview-generated-overview-output"
    static let overviewRetrySave = "advanced-settings-overview-generated-retry-save"
    static let replaceRetrySave = "advanced-settings-repository-config-retry-save"
    static let genericRetrySave = "advanced-settings-retry-save"
}

struct AdvancedSettingsDraft: Equatable {
    var overviewOutput: AdvancedSettingsOverviewOutput
    var allowReplaceDuringImport: Bool

    init(config: RepoConfigSnapshot) {
        overviewOutput = AdvancedSettingsOverviewOutput(snapshotValue: config.overviewOutput)
        allowReplaceDuringImport = config.allowReplaceDuringImport
    }
}

struct AdvancedSettingsPendingSave: Equatable {
    var config: RepoConfigSnapshot
    var kind: AdvancedSettingsSaveKind
}

extension RepoConfigSnapshot {
    func withAdvancedRepositoryPath(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.repoPath = value
        return config
    }

    func withAdvancedOverviewOutput(_ value: String) -> RepoConfigSnapshot {
        var config = self
        config.overviewOutput = value
        return config
    }

    func withAdvancedAllowReplaceDuringImport(_ value: Bool) -> RepoConfigSnapshot {
        var config = self
        config.allowReplaceDuringImport = value
        return config
    }
}
