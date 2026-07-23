import Foundation

struct ImportBatchSessionSnapshot: Equatable {
    var repoPath: String
    var storageMode: ImportSingleFileStorageMode
    var completed: Int
    var failed: Int
    var total: Int
    var currentPath: String
    var items: [ImportBatchProgressSnapshot.Item]

    var isUnfinishedCopySession: Bool {
        storageMode == .copy && completed + failed < total
    }

    var progressSnapshot: ImportBatchProgressSnapshot {
        ImportBatchProgressSnapshot(
            completed: completed,
            failed: failed,
            total: total,
            remaining: max(total - completed - failed, 0),
            currentPath: currentPath,
            items: items
        )
    }
}

protocol ImportBatchSessionPersisting {
    func saveSession(_ session: ImportBatchSessionSnapshot) async
    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot?
    func clearSession(repoPath: String) async
}

/// Stable recovery data for an import failure. The catalog key is deliberately
/// resolved only when the recovered row is presented again.
struct ImportBatchSessionFailureDescriptor: Codable, Equatable {
    enum Code: String, Codable, Equatable {
        case io
        case database
        case configuration
        case validation
        case classification
        case conflict
        case duplicateFile = "duplicate-file"
        case fileNotFound = "file-not-found"
        case expiredAction = "expired-action"
        case repositoryNotInitialized = "repository-not-initialized"
        case invalidPath = "invalid-path"
        case iCloudPlaceholder = "icloud-placeholder"
        case stagingRecoveryRequired = "staging-recovery-required"
        case permissionDenied = "permission-denied"
        case internalFailure = "internal"
        case importFailed = "import-failed"
        case technicalDetail = "technical-detail"
    }

    struct Payload: Codable, Equatable {
        var technicalDetail: String?
    }

    let code: Code
    let payload: Payload

    init(code: Code, technicalDetail: String? = nil) {
        self.code = code
        payload = Payload(technicalDetail: technicalDetail)
    }

    init(displayText: AppDisplayText) {
        switch displayText {
        case let .verbatim(value, _):
            self.init(code: .technicalDetail, technicalDetail: value)
        case let .localized(message):
            self.init(
                code: Self.code(for: message.key),
                technicalDetail: message.technicalDetail
            )
        }
    }

    var displayText: AppDisplayText {
        switch code {
        case .io: .localized(L10n.message("core.error.Io.message"))
        case .database: .localized(L10n.message("core.error.Db.message"))
        case .configuration: .localized(L10n.message("core.error.Config.message"))
        case .validation: .localized(L10n.message("core.error.Validation.message"))
        case .classification: .localized(L10n.message("core.error.Classify.message"))
        case .conflict: .localized(L10n.message("core.error.Conflict.message"))
        case .duplicateFile: .localized(L10n.message("core.error.DuplicateFile.message"))
        case .fileNotFound: .localized(L10n.message("core.error.FileNotFound.message"))
        case .expiredAction: .localized(L10n.message("core.error.ExpiredAction.message"))
        case .repositoryNotInitialized: .localized(L10n.message("core.error.RepoNotInitialized.message"))
        case .invalidPath: .localized(L10n.message("core.error.InvalidPath.message"))
        case .iCloudPlaceholder: .localized(L10n.message("core.error.ICloudPlaceholder.message"))
        case .stagingRecoveryRequired:
            .localized(L10n.message("core.error.StagingRecoveryRequired.message"))
        case .permissionDenied: .localized(L10n.message("core.error.PermissionDenied.message"))
        case .internalFailure: .localized(L10n.message("core.error.Internal.message"))
        case .importFailed: .localized(L10n.message("Import failed"))
        case .technicalDetail:
            .verbatim(payload.technicalDetail ?? L10n.string("Import failed"), reason: .technicalDetail)
        }
    }

    private static func code(for key: String) -> Code {
        switch key {
        case "core.error.Io.message": .io
        case "core.error.Db.message": .database
        case "core.error.Config.message": .configuration
        case "core.error.Validation.message": .validation
        case "core.error.Classify.message": .classification
        case "core.error.Conflict.message": .conflict
        case "core.error.DuplicateFile.message": .duplicateFile
        case "core.error.FileNotFound.message": .fileNotFound
        case "core.error.ExpiredAction.message": .expiredAction
        case "core.error.RepoNotInitialized.message": .repositoryNotInitialized
        case "core.error.InvalidPath.message": .invalidPath
        case "core.error.ICloudPlaceholder.message": .iCloudPlaceholder
        case "core.error.StagingRecoveryRequired.message": .stagingRecoveryRequired
        case "core.error.PermissionDenied.message": .permissionDenied
        case "core.error.Internal.message": .internalFailure
        default: .importFailed
        }
    }
}

extension ImportBatchSessionSnapshot {
    var interruptedProgressSnapshot: ImportBatchProgressSnapshot {
        let resolvedItems = items.map { item in
            guard item.phase != .done, item.phase != .failed else { return item }
            var pendingItem = item
            pendingItem.phase = .pending
            pendingItem.errorDisplayText = .localized(L10n.message("Import not completed before AreaMatrix quit"))
            return pendingItem
        }
        return ImportBatchProgressSnapshot(
            completed: completed,
            failed: failed,
            total: total,
            remaining: max(total - completed - failed, 0),
            currentPath: currentPath,
            items: resolvedItems
        )
    }
}
