import AreaMatrixCoreSDK

struct SyncConflictEntryCoreFFIClient {
    func detectSyncConflicts(repoPath: String) throws -> [SyncConflictEntryConflict] {
        do {
            return try AreaMatrixCoreSDK.detectSyncConflicts(repoPath: repoPath)
                .map(SyncConflictCoreSDKMapping.conflict)
        } catch {
            throw SyncConflictCoreSDKMapping.error(error)
        }
    }
}

enum SyncConflictCoreSDKMapping {
    static func conflict(_ value: AreaMatrixCoreSDK.SyncConflict) -> SyncConflictEntryConflict {
        SyncConflictEntryConflict(
            conflictID: value.conflictId,
            conflictType: type(value.conflictType),
            severity: severity(value.severity),
            status: status(value.status),
            primaryPath: value.primaryPath,
            affectedFiles: value.affectedFiles.map(affectedFile),
            versionCount: value.versionCount,
            sourceProvider: value.sourceProvider,
            detectedAt: value.detectedAt,
            summary: value.summary
        )
    }

    static func affectedFile(
        _ value: AreaMatrixCoreSDK.SyncConflictAffectedFile
    ) -> SyncConflictEntryAffectedFile {
        SyncConflictEntryAffectedFile(
            path: value.path,
            fileID: value.fileId,
            role: role(value.role),
            sizeBytes: value.sizeBytes,
            modifiedAt: value.modifiedAt,
            hashSha256: value.hashSha256,
            sourcePlatform: value.sourcePlatform
        )
    }

    static func versionImpact(
        _ value: AreaMatrixCoreSDK.SyncConflictVersionImpact
    ) -> SyncConflictVersionImpact {
        SyncConflictVersionImpact(
            path: value.path,
            fileID: value.fileId,
            role: role(value.role),
            willKeep: value.willKeep,
            willBeCanonical: value.willBeCanonical,
            willRemainUserVisible: value.willRemainUserVisible,
            willMoveToTrash: value.willMoveToTrash,
            recoveryTarget: value.recoveryTarget,
            reason: value.reason
        )
    }

    static func replacePlan(
        _ value: AreaMatrixCoreSDK.SyncConflictReplacePlan
    ) -> SyncConflictReplacePlan {
        SyncConflictReplacePlan(
            oldPath: value.oldPath,
            newPath: value.newPath,
            oldHashSha256: value.oldHashSha256,
            newHashSha256: value.newHashSha256,
            affectedFileID: value.affectedFileId,
            backupTarget: value.backupTarget,
            databaseUpdate: value.databaseUpdate,
            changeLogAction: value.changeLogAction,
            recoveryNote: value.recoveryNote
        )
    }

    static func preview(
        _ value: AreaMatrixCoreSDK.SyncConflictResolutionPreviewReport
    ) -> SyncConflictResolutionPreviewReport {
        SyncConflictResolutionPreviewReport(
            conflictID: value.conflictId,
            resolution: resolution(value.resolution),
            defaultResolution: resolution(value.defaultResolution),
            statusAfter: status(value.statusAfter),
            versionImpacts: value.versionImpacts.map(versionImpact),
            keptPaths: value.keptPaths,
            retainedPaths: value.retainedPaths,
            plannedTrashPaths: value.plannedTrashPaths,
            affectedFileIDs: value.affectedFileIds,
            canonicalPath: value.canonicalPath,
            changeLogAction: value.changeLogAction,
            destructive: value.destructive,
            requiresReplaceConfirmation: value.requiresReplaceConfirmation,
            trashRequired: value.trashRequired,
            trashAvailable: value.trashAvailable,
            canApply: value.canApply,
            blockedReason: value.blockedReason,
            previewToken: value.previewToken,
            replacePlan: value.replacePlan.map(replacePlan)
        )
    }

    static func resolve(
        _ value: AreaMatrixCoreSDK.SyncConflictResolveReport
    ) -> SyncConflictResolveReport {
        SyncConflictResolveReport(
            conflictID: value.conflictId,
            resolution: resolution(value.resolution),
            status: status(value.status),
            keptPaths: value.keptPaths,
            retainedPaths: value.retainedPaths,
            trashedPaths: value.trashedPaths,
            affectedFileIDs: value.affectedFileIds,
            changeLogAction: value.changeLogAction,
            undoToken: value.undoToken,
            resolvedAt: value.resolvedAt
        )
    }

    static func sdkResolution(
        _ value: SyncConflictResolutionStrategy
    ) -> AreaMatrixCoreSDK.SyncConflictResolutionStrategy {
        switch value {
        case .keepBoth:
            .keepBoth
        case .useExisting:
            .useExisting
        case .useIncoming:
            .useIncoming
        }
    }

    static func sdkRequest(
        _ value: SyncConflictResolutionRequest
    ) -> AreaMatrixCoreSDK.SyncConflictResolutionRequest {
        AreaMatrixCoreSDK.SyncConflictResolutionRequest(
            strategy: sdkResolution(value.strategy),
            previewToken: value.previewToken,
            replaceConfirmed: value.replaceConfirmed,
            replaceConfirmationId: value.replaceConfirmationID
        )
    }

    private static func type(
        _ value: AreaMatrixCoreSDK.SyncConflictType
    ) -> SyncConflictEntryType {
        switch value {
        case .sameNameDifferentContent:
            .sameNameDifferentContent
        case .concurrentModification:
            .concurrentModification
        case .metadataMismatch:
            .metadataMismatch
        case .missingVersion:
            .missingVersion
        case .unknown:
            .unknown
        }
    }

    private static func severity(
        _ value: AreaMatrixCoreSDK.SyncConflictSeverity
    ) -> SyncConflictEntrySeverity {
        switch value {
        case .low:
            .low
        case .medium:
            .medium
        case .high:
            .high
        }
    }

    private static func status(
        _ value: AreaMatrixCoreSDK.SyncConflictStatus
    ) -> SyncConflictEntryStatus {
        switch value {
        case .needsReview:
            .needsReview
        case .resolved:
            .resolved
        }
    }

    private static func role(
        _ value: AreaMatrixCoreSDK.SyncConflictFileRole
    ) -> SyncConflictEntryFileRole {
        switch value {
        case .existing:
            .existing
        case .incoming:
            .incoming
        case .conflictCopy:
            .conflictCopy
        case .missing:
            .missing
        case .unknown:
            .unknown
        }
    }

    private static func resolution(
        _ value: AreaMatrixCoreSDK.SyncConflictResolutionStrategy
    ) -> SyncConflictResolutionStrategy {
        switch value {
        case .keepBoth:
            .keepBoth
        case .useExisting:
            .useExisting
        case .useIncoming:
            .useIncoming
        }
    }

    static func error(_ error: Error) -> SyncConflictEntryError {
        if let entryError = error as? SyncConflictEntryError {
            return entryError
        }
        guard let coreError = error as? AreaMatrixCoreSDK.CoreError else {
            return .unavailable(error.localizedDescription)
        }
        switch coreError {
        case let .Io(message):
            return .io(message)
        case let .Db(message), let .DbLocked(message), let .DbCorrupted(message):
            return .database(message)
        case let .Conflict(path):
            return .conflict(path)
        case let .PermissionDenied(path):
            return .permissionDenied(path)
        default:
            return .unavailable(String(describing: coreError))
        }
    }
}
