import Foundation

enum FilesImportConflictStrategy: String, CaseIterable, Identifiable, Equatable {
    case skip
    case keepBoth
    case replace

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .skip:
            "Skip duplicate"
        case .keepBoth:
            "Keep both"
        case .replace:
            "Replace existing file"
        }
    }

    var detail: String {
        switch self {
        case .skip:
            "Keep the existing repository file and do not import this item."
        case .keepBoth:
            "Import with an automatically numbered filename."
        case .replace:
            "Requires Core Trash preflight and a second confirmation."
        }
    }
}

enum FilesImportConflictKind: Equatable {
    case duplicateContent
    case nameConflict

    var title: String {
        switch self {
        case .duplicateContent:
            "Duplicate content"
        case .nameConflict:
            "Name conflict"
        }
    }

    var defaultStrategy: FilesImportConflictStrategy {
        switch self {
        case .duplicateContent:
            .skip
        case .nameConflict:
            .keepBoth
        }
    }

    var availableStrategies: [FilesImportConflictStrategy] {
        switch self {
        case .duplicateContent:
            [.skip, .replace]
        case .nameConflict:
            [.keepBoth, .replace]
        }
    }
}

struct FilesImportReplaceCandidate: Equatable, Identifiable {
    var id: String { itemID }

    var itemID: String
    var kind: FilesImportConflictKind
    var existingPath: String
    var incomingPath: String
    var incomingName: String
    var incomingSizeBytes: Int64?
    var targetRelativePath: String
    var keepBothFilename: String?
    var isConfirmed = false
    var replacePlan: FilesImportReplacePlan?

    var defaultStrategy: FilesImportConflictStrategy {
        kind.defaultStrategy
    }

    var safeResolutionSummary: String {
        switch kind {
        case .duplicateContent:
            "Default: Skip duplicate."
        case .nameConflict:
            "Default: Keep both as \(keepBothFilename ?? incomingName)."
        }
    }

    var replaceBlockedReason: String? {
        guard let replacePlan else { return nil }
        return replacePlan.canReplace ? nil : replacePlan.blockedReason
    }
}

struct FilesImportReplaceConfirmation: Equatable, Identifiable {
    var id: String { candidate.id }
    var candidate: FilesImportReplaceCandidate

    var plan: FilesImportReplacePlan {
        candidate.replacePlan ?? FilesImportReplacePlan(
            confirmationID: "missing-plan",
            oldPath: candidate.existingPath,
            newPath: candidate.targetRelativePath,
            oldHashSHA256: nil,
            newHashSHA256: nil,
            affectedFileID: -1,
            backupTarget: "Unavailable",
            databaseUpdate: "No database update will be applied.",
            changeLogAction: "none",
            recoveryNote: "Replace plan expired. Re-run Core preflight.",
            trashAvailable: false,
            undoAvailable: false,
            canReplace: false,
            blockedReason: "Replace plan expired. Re-run Core preflight.",
            previewToken: ""
        )
    }
}
