import Foundation

protocol FilesImportCoreBridge: Sendable {
    func predictCategory(repoPath: String, filename: String) async throws -> FilesImportCategoryPrediction
    func importSelectedFile(request: FilesImportCoreRequest) async throws -> MobileLibraryFile
    func prepareReplace(request: FilesImportReplacePlanRequest) async throws -> FilesImportReplacePlan
    func replaceSelectedFile(request: FilesImportReplaceRequest) async throws -> FilesImportReplaceExecutionReport
}

struct FilesImportCategoryPrediction: Equatable, Sendable {
    var category: String
    var suggestedName: String
    var confidence: Float
}

struct FilesImportCoreRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var filename: String
    var category: String
    var duplicateStrategy: FilesImportDuplicateStrategy
}

struct FilesImportReplacePlanRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var incomingName: String
    var category: String
    var existingPath: String
    var targetRelativePath: String
}

struct FilesImportReplaceRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var filename: String
    var category: String
    var plan: FilesImportReplacePlan
}

struct FilesImportReplacePlan: Equatable, Sendable {
    var confirmationID: String
    var oldPath: String
    var newPath: String
    var oldHashSHA256: String?
    var newHashSHA256: String?
    var affectedFileID: Int64
    var backupTarget: String
    var databaseUpdate: String
    var changeLogAction: String
    var recoveryNote: String
    var trashAvailable: Bool
    var undoAvailable: Bool
    var canReplace: Bool
    var blockedReason: String?
    var previewToken: String
}

struct FilesImportReplaceExecutionReport: Equatable, Sendable {
    var importedFile: MobileLibraryFile
    var oldFileID: Int64
    var oldPath: String
    var newPath: String
    var oldHashSHA256: String?
    var newHashSHA256: String?
    var backupTarget: String
    var databaseUpdate: String
    var changeLogAction: String
    var recoveryNote: String
    var undoToken: String?
    var affectedFileIDs: [Int64]

    var statusSummary: String {
        if let undoToken {
            return "Replaced \(oldPath). Undo token: \(undoToken)."
        }
        return "Replaced \(oldPath). Restore from Trash if recovery is needed."
    }
}

enum FilesImportDuplicateStrategy: Equatable, Sendable {
    case skip
    case overwrite
    case keepBoth
}

enum FilesImportError: Error, Equatable, Sendable {
    case emptySelection
    case unreadableFile(String)
    case iCloudPlaceholder(String)
    case duplicateContent(String)
    case nameConflict(String)
    case invalidPath(String)
    case permissionDenied(String)
    case database(String)
    case replaceUnavailable(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .emptySelection:
            "Choose files to import."
        case .unreadableFile:
            "One or more selected files cannot be read."
        case .iCloudPlaceholder:
            "Download needed before importing this file."
        case .duplicateContent:
            "Duplicate content was skipped."
        case .nameConflict:
            "A name conflict needs review."
        case .invalidPath:
            "The selected file path or file name is invalid."
        case .permissionDenied:
            "AreaMatrix does not have permission to read this file or repository."
        case let .database(message):
            message.isEmpty ? "Repository metadata could not be updated." : message
        case let .replaceUnavailable(message):
            message.isEmpty ? "Replace requires a recoverable old-file path." : message
        case let .unavailable(message):
            message.isEmpty ? "Files import failed." : message
        }
    }

    static func map(_ error: Error) -> FilesImportError {
        if let filesError = error as? FilesImportError {
            return filesError
        }
        return .unavailable(error.localizedDescription)
    }
}

extension LiveMobileRepositoryCoreBridge: FilesImportCoreBridge {
    func predictCategory(repoPath: String, filename: String) async throws -> FilesImportCategoryPrediction {
        try FilesImportCoreFFIClient().predictCategory(repoPath: repoPath, filename: filename)
    }

    func importSelectedFile(request: FilesImportCoreRequest) async throws -> MobileLibraryFile {
        try await Task.detached(priority: .userInitiated) {
            try FilesImportCoreFFIClient().importSelectedFile(request: request)
        }.value
    }

    func prepareReplace(request: FilesImportReplacePlanRequest) async throws -> FilesImportReplacePlan {
        try await Task.detached(priority: .userInitiated) {
            try FilesImportReplaceCoreFFIClient().prepareReplace(request: request)
        }.value
    }

    func replaceSelectedFile(request: FilesImportReplaceRequest) async throws -> FilesImportReplaceExecutionReport {
        try await Task.detached(priority: .userInitiated) {
            try FilesImportReplaceCoreFFIClient().replaceSelectedFile(request: request)
        }.value
    }
}
