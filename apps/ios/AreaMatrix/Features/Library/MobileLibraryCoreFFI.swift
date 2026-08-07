import AreaMatrixCoreSDK

struct MobileLibraryCoreFFIClient {
    func listFiles(repoPath: String, filter: MobileLibraryFileFilter) throws -> [MobileLibraryFile] {
        do {
            let sdkFilter = AreaMatrixCoreSDK.FileFilter(
                category: filter.category,
                includeDeleted: filter.includeDeleted,
                importedAfter: filter.importedAfter,
                importedBefore: filter.importedBefore,
                limit: filter.limit,
                offset: filter.offset
            )
            return try AreaMatrixCoreSDK.listFiles(repoPath: repoPath, filter: sdkFilter)
                .map(MobileLibraryCoreSDKMapping.file)
        } catch {
            throw MobileLibraryCoreSDKMapping.error(error)
        }
    }

    func listTreeJSON(repoPath: String, locale: String) throws -> String {
        do {
            return try AreaMatrixCoreSDK.listTreeJson(repoPath: repoPath, locale: locale)
        } catch {
            throw MobileLibraryCoreSDKMapping.error(error)
        }
    }
}

enum MobileLibraryCoreSDKMapping {
    static func file(_ value: AreaMatrixCoreSDK.FileEntry) -> MobileLibraryFile {
        MobileLibraryFile(
            id: value.id,
            path: value.path,
            originalName: value.originalName,
            currentName: value.currentName,
            category: value.category,
            sizeBytes: value.sizeBytes,
            hashSha256: value.hashSha256,
            storageMode: storageMode(value.storageMode),
            origin: origin(value.origin),
            sourcePath: value.sourcePath,
            availability: availability(value.availabilityStatus),
            importedAt: value.importedAt,
            updatedAt: value.updatedAt
        )
    }

    static func storageMode(_ value: AreaMatrixCoreSDK.StorageMode) -> String {
        switch value {
        case .moved:
            "Moved"
        case .copied:
            "Copied"
        case .indexed:
            "Indexed"
        }
    }

    static func origin(_ value: AreaMatrixCoreSDK.FileOrigin) -> String {
        switch value {
        case .imported:
            "Imported"
        case .adopted:
            "Adopted"
        case .external:
            "External"
        }
    }

    static func availability(
        _ value: AreaMatrixCoreSDK.FileAvailabilityStatus
    ) -> MobileLibraryFileAvailability {
        switch value {
        case .available:
            .available
        case .missing:
            .missing
        }
    }

    static func error(_ error: Error) -> MobileLibraryQueryError {
        if let queryError = error as? MobileLibraryQueryError {
            return queryError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable(error.localizedDescription)
        }
        switch coreError {
        case let .RepoNotInitialized(path):
            return .repoNotInitialized(path)
        case let .Db(message), let .DbLocked(message), let .DbCorrupted(message):
            return .database(message)
        default:
            return .unavailable(String(describing: coreError))
        }
    }
}
