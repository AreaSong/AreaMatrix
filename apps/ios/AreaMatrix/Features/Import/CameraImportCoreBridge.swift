import Foundation

protocol CameraImportCoreBridge: Sendable {
    func predictCategory(repoPath: String, filename: String) async throws -> CameraImportCategoryPrediction
    func importCapturedPhoto(request: CameraImportCoreRequest) async throws -> MobileLibraryFile
}

struct CameraImportCategoryPrediction: Equatable, Sendable {
    var category: String
    var suggestedName: String
    var confidence: Float
}

struct CameraImportCoreRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var filename: String
    var category: String
    var duplicateStrategy: CameraImportDuplicateStrategy
}

enum CameraImportDuplicateStrategy: Equatable, Sendable {
    case skip
    case keepBoth
}

enum CameraImportError: Error, Equatable, Sendable {
    case duplicateContent(String)
    case nameConflict(String)
    case invalidPath(String)
    case permissionDenied(String)
    case unreadableSource(String)
    case database(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .duplicateContent:
            "Duplicate content"
        case .nameConflict:
            "Name conflict"
        case .invalidPath:
            "Could not read captured photo."
        case .permissionDenied:
            "Camera photo or repository permission was denied."
        case .unreadableSource:
            "Could not read captured photo."
        case let .database(message):
            message.isEmpty ? "Repository metadata could not be updated." : message
        case let .unavailable(message):
            message.isEmpty ? "Photo import failed." : message
        }
    }

    static func map(_ error: Error) -> CameraImportError {
        if let importError = error as? CameraImportError {
            return importError
        }
        return .unavailable(error.localizedDescription)
    }
}

extension LiveMobileRepositoryCoreBridge: CameraImportCoreBridge {
    func predictCategory(repoPath: String, filename: String) async throws -> CameraImportCategoryPrediction {
        try CameraImportCoreFFIClient().predictCategory(repoPath: repoPath, filename: filename)
    }

    func importCapturedPhoto(request: CameraImportCoreRequest) async throws -> MobileLibraryFile {
        try await Task.detached(priority: .userInitiated) {
            try CameraImportCoreFFIClient().importCapturedPhoto(request: request)
        }.value
    }
}
