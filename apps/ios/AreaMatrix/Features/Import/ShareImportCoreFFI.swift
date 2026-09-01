import AreaMatrixCoreSDK

struct ShareImportCoreFFIClient {
    func predictCategory(repoPath: String, filename: String) throws -> ShareImportCategoryPrediction {
        do {
            let result = try AreaMatrixCoreSDK.predictCategory(repoPath: repoPath, filename: filename)
            return ShareImportCategoryPrediction(
                category: result.category,
                suggestedName: result.suggestedName,
                confidence: result.confidence
            )
        } catch {
            throw ShareImportCoreSDKMapping.error(error)
        }
    }

    func importSharedItem(request: ShareImportCoreRequest) throws -> MobileLibraryFile {
        do {
            let contentLocale = try MobileRepositoryCoreFFIClient().contentLocale(repoPath: request.repoPath)
            let options = FilesImportCoreSDKMapping.importOptions(
                category: request.category,
                filename: request.filename,
                duplicateStrategy: .skip,
                contentLocale: contentLocale
            )
            return MobileLibraryCoreSDKMapping.file(
                try AreaMatrixCoreSDK.importFile(
                    repoPath: request.repoPath,
                    sourcePath: request.sourceURL.path,
                    options: options
                )
            )
        } catch {
            throw ShareImportCoreSDKMapping.error(error)
        }
    }
}

enum ShareImportCoreSDKMapping {
    static func error(_ error: Error) -> ShareImportError {
        if let shareError = error as? ShareImportError {
            return shareError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable("Share import is unavailable.")
        }
        switch coreError {
        case let .Io(message):
            return .io(message)
        case let .Conflict(path), let .RevisionConflict(path, _, _):
            return .conflictNeedsReview(path)
        case let .InvalidPath(path), let .FileNotFound(path):
            return .invalidPath(path)
        case let .PermissionDenied(path):
            return .permissionDenied(path)
        case .RepoNotInitialized:
            return .noRepository
        case let .ExpiredAction(path):
            return .permissionExpired(path)
        default:
            return .unavailable("Share import is unavailable.")
        }
    }
}
