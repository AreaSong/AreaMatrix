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
            "Generated only"
        case .rootAreaMatrixFile:
            "Root AREAMATRIX.md"
        }
    }
}

enum AdvancedSettingsSaveKind: Equatable {
    case overview
    case replace

    var message: String {
        switch self {
        case .overview:
            "Could not save overview setting"
        case .replace:
            "Could not save advanced setting"
        }
    }
}

struct AdvancedSettingsError: Equatable {
    var message: String
    var recovery: String
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
