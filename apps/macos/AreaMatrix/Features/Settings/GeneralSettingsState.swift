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
            L10n.string("Copy (recommended)")
        case .move:
            L10n.string("Move")
        case .indexOnly:
            L10n.string("Index-only")
        }
    }

    var confirmationMessage: String? {
        switch self {
        case .copy:
            nil
        case .move:
            L10n.string("Imported source files will disappear from their original location after import.")
        case .indexOnly:
            L10n.string("Moving source files later can make indexed entries missing.")
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

enum GeneralSettingsAppearance: String, CaseIterable, Equatable, Identifiable {
    case system

    var id: String {
        rawValue
    }

    var label: String {
        L10n.string("system")
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
            L10n.string("A new AREAMATRIX.md will be created at the repository root.")
        case .managedBlock:
            L10n.string("Only the AreaMatrix managed block will be updated.")
        case .userContent:
            [
                L10n.string("AreaMatrix will append a clearly marked managed block to AREAMATRIX.md."),
                L10n.string("Existing content will remain unchanged.")
            ].joined(separator: " ")
        case let .unsafe(reason):
            reason.isEmpty ? L10n.string("Cannot safely update AREAMATRIX.md") : reason
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
    var message: LocalizedMessage
    var recovery: LocalizedMessage
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
    var appearance: GeneralSettingsAppearance

    init(config: RepoConfigSnapshot) {
        defaultStorageMode = GeneralSettingsStorageMode(snapshotValue: config.defaultMode)
        overviewOutput = GeneralSettingsOverviewOutput(snapshotValue: config.overviewOutput)
        appearance = .system
    }
}
