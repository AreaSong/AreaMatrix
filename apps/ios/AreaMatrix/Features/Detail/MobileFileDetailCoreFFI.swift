import AreaMatrixCoreSDK

struct MobileFileDetailCoreFFIClient {
    func getFile(repoPath: String, fileID: Int64) throws -> MobileFileDetailMetadata {
        do {
            return MobileFileDetailCoreSDKMapping.metadata(
                try AreaMatrixCoreSDK.getFile(repoPath: repoPath, fileId: fileID)
            )
        } catch {
            throw MobileFileDetailCoreSDKMapping.error(error)
        }
    }

    func listChanges(
        repoPath: String,
        filter: MobileFileDetailChangeFilter
    ) throws -> [MobileFileChangeLogEntry] {
        do {
            let sdkFilter = AreaMatrixCoreSDK.ChangeFilter(
                fileId: filter.fileID,
                category: filter.category,
                action: filter.action,
                since: filter.since,
                until: filter.until,
                limit: filter.limit,
                offset: filter.offset
            )
            return try AreaMatrixCoreSDK.listChanges(repoPath: repoPath, filter: sdkFilter)
                .map(MobileFileDetailCoreSDKMapping.change)
        } catch {
            throw MobileFileDetailCoreSDKMapping.error(error)
        }
    }

    func readNote(repoPath: String, fileID: Int64) throws -> String? {
        do {
            return try AreaMatrixCoreSDK.readNote(repoPath: repoPath, fileId: fileID)
        } catch {
            throw MobileFileDetailCoreSDKMapping.error(error)
        }
    }
}

enum MobileFileDetailCoreSDKMapping {
    static func metadata(
        _ value: AreaMatrixCoreSDK.FileEntry
    ) -> MobileFileDetailMetadata {
        MobileFileDetailMetadata(
            id: value.id,
            path: value.path,
            originalName: value.originalName,
            currentName: value.currentName,
            category: value.category,
            sizeBytes: value.sizeBytes,
            hashSha256: value.hashSha256,
            storageMode: MobileLibraryCoreSDKMapping.storageMode(value.storageMode),
            origin: MobileLibraryCoreSDKMapping.origin(value.origin),
            sourcePath: value.sourcePath,
            availability: availability(value.availabilityStatus),
            importedAt: value.importedAt,
            updatedAt: value.updatedAt
        )
    }

    static func change(
        _ value: AreaMatrixCoreSDK.ChangeLogEntry
    ) -> MobileFileChangeLogEntry {
        MobileFileChangeLogEntry(
            id: value.id,
            fileID: value.fileId,
            filename: value.filename,
            category: value.category,
            action: value.action,
            detailJSON: value.detailJson,
            occurredAt: value.occurredAt
        )
    }

    private static func availability(
        _ value: AreaMatrixCoreSDK.FileAvailabilityStatus
    ) -> MobileFileDetailAvailability {
        switch value {
        case .available:
            .available
        case .missing:
            .missing
        }
    }

    static func error(_ error: Error) -> MobileFileDetailError {
        if let detailError = error as? MobileFileDetailError {
            return detailError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable(error.localizedDescription)
        }
        switch coreError {
        case let .FileNotFound(path):
            return .fileNotFound(path)
        case let .Db(message), let .DbLocked(message), let .DbCorrupted(message):
            return .database(message)
        case let .PermissionDenied(path):
            return .permissionDenied(path)
        default:
            return .unavailable(String(describing: coreError))
        }
    }
}
