import Foundation

enum GeneralSettingsStorageMode: String, CaseIterable, Equatable, Identifiable {
    case copy
    case move
    case indexOnly

    var id: String {
        rawValue
    }

    init(snapshotValue: String) {
        switch snapshotValue {
        case "Moved":
            self = .move
        case "Indexed":
            self = .indexOnly
        default:
            self = .copy
        }
    }

    var snapshotValue: String {
        switch self {
        case .copy:
            "Copied"
        case .move:
            "Moved"
        case .indexOnly:
            "Indexed"
        }
    }

    var label: String {
        switch self {
        case .copy:
            "Copy (recommended)"
        case .move:
            "Move"
        case .indexOnly:
            "Index-only"
        }
    }

    var confirmationMessage: String? {
        switch self {
        case .copy:
            nil
        case .move:
            "Imported source files will disappear from their original location after import."
        case .indexOnly:
            "Moving source files later can make indexed entries missing."
        }
    }
}

enum GeneralSettingsOverviewOutput: String, CaseIterable, Equatable, Identifiable {
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
}

enum GeneralSettingsLocale: String, CaseIterable, Equatable, Identifiable {
    case system
    case zhCN
    case en

    var id: String {
        rawValue
    }

    init(snapshotValue: String) {
        switch snapshotValue.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "en":
            self = .en
        case "zh-CN":
            self = .zhCN
        case "system":
            self = .system
        case "zh-Hans":
            self = .zhCN
        default:
            self = .system
        }
    }

    var snapshotValue: String {
        switch self {
        case .system:
            "system"
        case .zhCN:
            "zh-CN"
        case .en:
            "en"
        }
    }

    var label: String {
        switch self {
        case .system:
            "system"
        case .zhCN:
            "zh-CN"
        case .en:
            "en"
        }
    }
}

enum GeneralSettingsAppearance: String, CaseIterable, Equatable, Identifiable {
    case system

    var id: String {
        rawValue
    }

    var label: String {
        "system"
    }
}

enum RootOverviewFileStatus: Equatable {
    case missing
    case managedBlock
    case userContent
    case unsafe(String)

    var confirmationDetail: String {
        switch self {
        case .missing:
            "A new AREAMATRIX.md will be created at the repository root."
        case .managedBlock:
            "Only the AreaMatrix managed block will be updated."
        case .userContent:
            [
                "AreaMatrix will append a clearly marked managed block to AREAMATRIX.md.",
                "Existing content will remain unchanged."
            ].joined(separator: " ")
        case let .unsafe(reason):
            reason.isEmpty ? "Cannot safely update AREAMATRIX.md" : reason
        }
    }

    var canEnableRootOverview: Bool {
        if case .unsafe = self { return false }
        return true
    }

    var requiresFinderRecovery: Bool {
        if case .unsafe = self { return true }
        return false
    }
}

struct GeneralSettingsSaveError: Equatable {
    var message: String
    var recovery: String
}

enum GeneralSettingsIgnoreRulesAlert: Equatable {
    case createDefault
}

struct GeneralSettingsPendingSave: Equatable {
    var config: RepoConfigSnapshot
    var error: GeneralSettingsSaveError
}

struct GeneralSettingsDraft: Equatable {
    var defaultStorageMode: GeneralSettingsStorageMode
    var overviewOutput: GeneralSettingsOverviewOutput
    var locale: GeneralSettingsLocale
    var appearance: GeneralSettingsAppearance

    init(config: RepoConfigSnapshot) {
        defaultStorageMode = GeneralSettingsStorageMode(snapshotValue: config.defaultMode)
        overviewOutput = GeneralSettingsOverviewOutput(snapshotValue: config.overviewOutput)
        locale = GeneralSettingsLocale(snapshotValue: config.locale)
        appearance = .system
    }
}
