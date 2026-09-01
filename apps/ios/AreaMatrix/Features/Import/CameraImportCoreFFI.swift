import AreaMatrixCoreSDK

struct CameraImportCoreFFIClient {
    func predictCategory(repoPath: String, filename: String) throws -> CameraImportCategoryPrediction {
        do {
            let result = try AreaMatrixCoreSDK.predictCategory(repoPath: repoPath, filename: filename)
            return CameraImportCategoryPrediction(
                category: result.category,
                suggestedName: result.suggestedName,
                confidence: result.confidence
            )
        } catch {
            throw CameraImportCoreSDKMapping.error(error)
        }
    }

    func importCapturedPhoto(request: CameraImportCoreRequest) throws -> MobileLibraryFile {
        do {
            let contentLocale = try MobileRepositoryCoreFFIClient().contentLocale(repoPath: request.repoPath)
            let options = FilesImportCoreSDKMapping.importOptions(
                category: request.category,
                filename: request.filename,
                duplicateStrategy: request.duplicateStrategy == .keepBoth ? .keepBoth : .skip,
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
            throw CameraImportCoreSDKMapping.error(error)
        }
    }
}

enum CameraImportCoreSDKMapping {
    static func error(_ error: Error) -> CameraImportError {
        if let importError = error as? CameraImportError {
            return importError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable("Photo import is unavailable.")
        }
        switch coreError {
        case let .Io(message):
            return .unreadableSource(message)
        case .Db, .DbLocked, .DbCorrupted:
            return .database("")
        case let .Conflict(path), let .RevisionConflict(path, _, _):
            return .nameConflict(path)
        case let .DuplicateFile(path):
            return .duplicateContent(path)
        case let .InvalidPath(path), let .FileNotFound(path):
            return .invalidPath(path)
        case let .PermissionDenied(path):
            return .permissionDenied(path)
        default:
            return .unavailable("Photo import is unavailable.")
        }
    }
}
