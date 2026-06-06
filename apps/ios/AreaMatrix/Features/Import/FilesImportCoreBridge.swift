import Foundation

protocol FilesImportCoreBridge: Sendable {
    func predictCategory(repoPath: String, filename: String) async throws -> FilesImportCategoryPrediction
    func importSelectedFile(request: FilesImportCoreRequest) async throws -> MobileLibraryFile
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

enum FilesImportDuplicateStrategy: Equatable, Sendable {
    case skip
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
}
