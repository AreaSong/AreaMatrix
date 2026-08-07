import AreaMatrixCoreSDK

struct FilesImportCoreFFIClient {
    func predictCategory(repoPath: String, filename: String) throws -> FilesImportCategoryPrediction {
        do {
            return FilesImportCoreSDKMapping.prediction(
                try AreaMatrixCoreSDK.predictCategory(repoPath: repoPath, filename: filename)
            )
        } catch {
            throw FilesImportCoreSDKMapping.error(error)
        }
    }

    func importSelectedFile(request: FilesImportCoreRequest) throws -> MobileLibraryFile {
        do {
            let contentLocale = try MobileRepositoryCoreFFIClient().contentLocale(repoPath: request.repoPath)
            let options = FilesImportCoreSDKMapping.importOptions(
                category: request.category,
                filename: request.filename,
                duplicateStrategy: request.duplicateStrategy,
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
            throw FilesImportCoreSDKMapping.error(error)
        }
    }
}

enum FilesImportCoreSDKMapping {
    static func prediction(
        _ value: AreaMatrixCoreSDK.ClassifyResult
    ) -> FilesImportCategoryPrediction {
        FilesImportCategoryPrediction(
            category: value.category,
            suggestedName: value.suggestedName,
            confidence: value.confidence
        )
    }

    static func importOptions(
        category: String,
        filename: String,
        duplicateStrategy: FilesImportDuplicateStrategy,
        contentLocale: MobileRepositoryContentLocale
    ) -> AreaMatrixCoreSDK.ImportOptions {
        AreaMatrixCoreSDK.ImportOptions(
            mode: .copied,
            destination: .category,
            targetDirectory: nil,
            overrideCategory: category,
            overrideFilename: filename,
            duplicateStrategy: sdkDuplicateStrategy(duplicateStrategy),
            contentLocale: sdkContentLocale(contentLocale)
        )
    }

    static func sdkDuplicateStrategy(
        _ value: FilesImportDuplicateStrategy
    ) -> AreaMatrixCoreSDK.DuplicateStrategy {
        switch value {
        case .skip:
            .skip
        case .overwrite:
            .overwrite
        case .keepBoth:
            .keepBoth
        }
    }

    static func sdkContentLocale(
        _ value: MobileRepositoryContentLocale
    ) -> AreaMatrixCoreSDK.ContentLocale {
        switch value {
        case .zhHans:
            .zhHans
        case .en:
            .en
        }
    }

    static func error(_ error: Error) -> FilesImportError {
        if let filesError = error as? FilesImportError {
            return filesError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable(error.localizedDescription)
        }
        switch coreError {
        case let .Io(message):
            return .unreadableFile(message)
        case let .Db(message), let .DbLocked(message), let .DbCorrupted(message):
            return .database(message)
        case let .Conflict(path), let .RevisionConflict(path, _, _):
            return .nameConflict(path)
        case let .DuplicateFile(path):
            return .duplicateContent(path)
        case let .InvalidPath(path), let .FileNotFound(path):
            return .invalidPath(path)
        case let .ICloudPlaceholder(path):
            return .iCloudPlaceholder(path)
        case let .PermissionDenied(path):
            return .permissionDenied(path)
        default:
            return .unavailable(String(describing: coreError))
        }
    }
}
