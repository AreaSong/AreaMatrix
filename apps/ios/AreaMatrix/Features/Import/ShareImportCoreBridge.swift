import Foundation

protocol ShareImportCoreBridge: Sendable {
    func predictCategory(repoPath: String, filename: String) async throws -> ShareImportCategoryPrediction
    func importSharedItem(request: ShareImportCoreRequest) async throws -> MobileLibraryFile
}

struct ShareImportCategoryPrediction: Equatable, Sendable {
    var category: String
    var suggestedName: String
    var confidence: Float
}

struct ShareImportCoreRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var filename: String
    var category: String
}

enum ShareImportError: Error, Equatable, Sendable {
    case noRepository
    case permissionExpired(String)
    case unsupportedItem(String)
    case invalidPath(String)
    case permissionDenied(String)
    case io(String)
    case conflictNeedsReview(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .noRepository:
            "Open AreaMatrix to connect a repository."
        case .permissionExpired:
            "Open AreaMatrix to reconnect this repository."
        case .unsupportedItem:
            "No supported items to import."
        case .invalidPath:
            "The shared item path is not valid."
        case .permissionDenied:
            "AreaMatrix does not have permission to read this item or repository."
        case .io:
            "The shared item could not be read or saved."
        case .conflictNeedsReview:
            "This item needs conflict review in AreaMatrix."
        case let .unavailable(message):
            message.isEmpty ? "Share import is unavailable." : message
        }
    }

    var shouldOpenMainApp: Bool {
        switch self {
        case .noRepository, .permissionExpired, .permissionDenied, .conflictNeedsReview:
            true
        case .unsupportedItem, .invalidPath, .io, .unavailable:
            false
        }
    }

    var blocksPreparation: Bool {
        switch self {
        case .noRepository, .permissionExpired, .invalidPath, .permissionDenied:
            true
        case .unsupportedItem, .io, .conflictNeedsReview, .unavailable:
            false
        }
    }

    static func map(_ error: Error) -> ShareImportError {
        if let shareError = error as? ShareImportError {
            return shareError
        }
        return .unavailable(error.localizedDescription)
    }
}

extension LiveMobileRepositoryCoreBridge: ShareImportCoreBridge {
    func predictCategory(repoPath: String, filename: String) async throws -> ShareImportCategoryPrediction {
        try ShareImportCoreFFIClient().predictCategory(repoPath: repoPath, filename: filename)
    }

    func importSharedItem(request: ShareImportCoreRequest) async throws -> MobileLibraryFile {
        try await Task.detached(priority: .userInitiated) {
            try ShareImportCoreFFIClient().importSharedItem(request: request)
        }.value
    }
}
