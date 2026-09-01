import AreaMatrixCoreSDK

struct MissingFileRecoveryCoreFFIClient {
    func getMissingFileState(repoPath: String, fileID: Int64) throws -> MissingFileRecoveryState {
        do {
            return MissingFileRecoveryCoreSDKMapping.state(
                try AreaMatrixCoreSDK.getMissingFileState(repoPath: repoPath, fileId: fileID)
            )
        } catch {
            throw MissingFileRecoveryCoreSDKMapping.error(error)
        }
    }

    func relinkMissingFile(
        repoPath: String,
        request: MissingFileRelinkRequest
    ) throws -> MissingFileRecoveryReport {
        do {
            let sdkRequest = AreaMatrixCoreSDK.MissingFileRelinkRequest(
                fileId: request.fileID,
                newPath: request.newPath,
                confirmed: request.confirmed
            )
            return MissingFileRecoveryCoreSDKMapping.report(
                try AreaMatrixCoreSDK.relinkMissingFile(repoPath: repoPath, request: sdkRequest)
            )
        } catch {
            throw MissingFileRecoveryCoreSDKMapping.error(error)
        }
    }

    func removeMissingFileRecord(
        repoPath: String,
        request: MissingFileRemoveRecordRequest
    ) throws -> MissingFileRecoveryReport {
        do {
            let sdkRequest = AreaMatrixCoreSDK.MissingFileRemoveRecordRequest(
                fileId: request.fileID,
                confirmed: request.confirmed
            )
            return MissingFileRecoveryCoreSDKMapping.report(
                try AreaMatrixCoreSDK.removeMissingFileRecord(repoPath: repoPath, request: sdkRequest)
            )
        } catch {
            throw MissingFileRecoveryCoreSDKMapping.error(error)
        }
    }
}

enum MissingFileRecoveryCoreSDKMapping {
    static func state(
        _ value: AreaMatrixCoreSDK.MissingFileState
    ) -> MissingFileRecoveryState {
        MissingFileRecoveryState(
            fileID: value.fileId,
            relativePath: value.relativePath,
            lastKnownPath: value.lastKnownPath,
            lastSeenAt: value.lastSeenAt,
            reason: reason(value.reason),
            expectedHashSha256: value.expectedHashSha256,
            canLocate: value.canLocate,
            canTryAgain: value.canTryAgain,
            canRemoveRecord: value.canRemoveRecord,
            removeRecordRequiresConfirmation: value.removeRecordRequiresConfirmation,
            canRunRescan: value.canRunRescan,
            rescanDisabledReason: value.rescanDisabledReason
        )
    }

    static func report(
        _ value: AreaMatrixCoreSDK.MissingFileRecoveryReport
    ) -> MissingFileRecoveryReport {
        MissingFileRecoveryReport(
            fileID: value.fileId,
            status: status(value.status),
            previousPath: value.previousPath,
            currentPath: value.currentPath,
            hashMatched: value.hashMatched,
            recordRemoved: value.recordRemoved,
            fileDeleted: value.fileDeleted,
            changeLogAction: value.changeLogAction,
            message: value.message
        )
    }

    private static func reason(
        _ value: AreaMatrixCoreSDK.MissingFileReason
    ) -> MissingFileReason {
        switch value {
        case .pathMissing:
            .pathMissing
        case .permissionDenied:
            .permissionDenied
        case .cloudPlaceholder:
            .cloudPlaceholder
        case .externalVolumeDisconnected:
            .externalVolumeDisconnected
        case .unknown:
            .unknown
        }
    }

    private static func status(
        _ value: AreaMatrixCoreSDK.MissingFileRecoveryStatus
    ) -> MissingFileRecoveryStatus {
        switch value {
        case .missing:
            .missing
        case .present:
            .present
        case .relinked:
            .relinked
        case .hashMismatch:
            .hashMismatch
        case .recordRemoved:
            .recordRemoved
        case .blocked:
            .blocked
        }
    }

    static func error(_ error: Error) -> MissingFileRecoveryError {
        if let recoveryError = error as? MissingFileRecoveryError {
            return recoveryError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable("Missing file recovery is unavailable.")
        }
        switch coreError {
        case let .FileNotFound(path):
            return .fileNotFound(path)
        case .Db, .DbLocked, .DbCorrupted:
            return .database("")
        case let .PermissionDenied(path):
            return .permissionDenied(path)
        default:
            return .unavailable("Missing file recovery is unavailable.")
        }
    }
}
