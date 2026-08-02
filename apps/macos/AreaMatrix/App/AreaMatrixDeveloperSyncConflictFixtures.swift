import Foundation

#if DEBUG
enum DeveloperSyncConflictScenarioFixture {
    static let repoPath = AreaMatrixPreviewFixtures.repositoryPath
    static let timestamp: Int64 = DeveloperFileActionScenarioFixture.timestamp

    static var iCloudPair: ICloudConflictPairSnapshot {
        ICloudConflictPairSnapshot(
            conflictID: "developer-icloud-conflict",
            originalPath: "docs/quarterly-report.pdf",
            conflictedCopyPath: "docs/quarterly-report (AreaMatrix conflict).pdf",
            originalModifiedAt: timestamp - 180,
            conflictedModifiedAt: timestamp,
            status: .needsReview,
            uncertaintyReason: nil
        )
    }

    static var iCloudPreview: ICloudConflictPreviewSnapshot {
        ICloudConflictPreviewSnapshot(
            conflictID: iCloudPair.conflictID,
            versions: [
                iCloudVersion(
                    id: "developer-original",
                    role: .original,
                    path: iCloudPair.originalPath ?? "docs/quarterly-report.pdf",
                    hash: "0123456789abcdef"
                ),
                iCloudVersion(
                    id: "developer-conflicted-copy",
                    role: .conflictedCopy,
                    path: iCloudPair.conflictedCopyPath,
                    hash: "fedcba9876543210"
                )
            ],
            defaultResolution: .keepBoth,
            resolutionOptions: ICloudConflictResolutionStrategy.allCases.map { strategy in
                ICloudConflictResolutionOptionSnapshot(
                    resolution: strategy,
                    destructive: strategy.requiresSecondConfirmation,
                    requiresTrash: strategy.requiresSecondConfirmation,
                    enabled: true,
                    disabledReason: nil
                )
            },
            metadataComplete: true,
            trashAvailable: true,
            canKeepBoth: true,
            canResolveDestructive: true,
            blockedReason: nil
        )
    }

    static var syncConflict: SyncConflictSnapshot {
        SyncConflictSnapshot(
            conflictID: "developer-sync-conflict",
            conflictType: .sameNameDifferentContent,
            severity: .high,
            status: .needsReview,
            primaryPath: "docs/quarterly-report.pdf",
            affectedFiles: [
                syncFile(
                    path: "docs/quarterly-report.pdf",
                    fileID: 1201,
                    role: .existing,
                    hash: "0123456789abcdef",
                    source: "macOS"
                ),
                syncFile(
                    path: "docs/quarterly-report (Windows conflict).pdf",
                    fileID: 2201,
                    role: .incoming,
                    hash: "fedcba9876543210",
                    source: "Windows"
                )
            ],
            versionCount: 2,
            sourceProvider: "OneDrive",
            detectedAt: timestamp,
            summary: DeveloperFileActionScenarioFixture.technicalDetail(
                "Two versions need review before one can become canonical."
            )
        )
    }

    static var replacePreview: SyncConflictResolutionPreviewSnapshot {
        syncPreview(resolution: .useIncoming)
    }

    static var pathValidation: RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: true,
            isInsideAreaMatrix: false,
            isICloudPath: true,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: 20 * 1024 * 1024 * 1024,
            isExternalVolume: false,
            recommendedMode: .adoptExisting,
            issues: [.alreadyInitialized, .iCloudPath]
        )
    }

    static func syncPreview(
        resolution: SyncConflictResolutionStrategySnapshot
    ) -> SyncConflictResolutionPreviewSnapshot {
        let replacing = resolution == .useIncoming
        return SyncConflictResolutionPreviewSnapshot(
            conflictID: syncConflict.conflictID,
            resolution: resolution,
            defaultResolution: .keepBoth,
            statusAfter: .resolved,
            versionImpacts: syncConflict.affectedFiles.map { file in
                SyncConflictVersionImpactSnapshot(
                    path: file.path,
                    fileID: file.fileID,
                    role: file.role,
                    willKeep: true,
                    willBeCanonical: replacing ? file.role == .incoming : file.role == .existing,
                    willRemainUserVisible: true,
                    willMoveToTrash: false,
                    recoveryTarget: nil,
                    reason: DeveloperFileActionScenarioFixture.technicalDetail(
                        "The developer scenario retains both fixture versions."
                    )
                )
            },
            keptPaths: syncConflict.affectedFiles.map(\.path),
            retainedPaths: syncConflict.affectedFiles.map(\.path),
            plannedTrashPaths: [],
            affectedFileIDs: syncConflict.affectedFiles.compactMap(\.fileID),
            canonicalPath: replacing
                ? "docs/quarterly-report (Windows conflict).pdf"
                : syncConflict.primaryPath,
            changeLogAction: replacing ? "sync_conflict_replaced" : "sync_conflict_resolved",
            destructive: replacing,
            requiresReplaceConfirmation: replacing,
            trashRequired: false,
            trashAvailable: false,
            canApply: true,
            blockedReason: nil,
            previewToken: "developer-preview-\(resolution.rawValue)",
            replacePlan: replacing ? SyncConflictReplacePlanSnapshot(
                oldPath: syncConflict.primaryPath,
                newPath: "docs/quarterly-report (Windows conflict).pdf",
                oldHashSha256: "0123456789abcdef",
                newHashSha256: "fedcba9876543210",
                affectedFileID: 1201,
                backupTarget: ".areamatrix/recovery/developer-quarterly-report.pdf",
                databaseUpdate: "Update the canonical metadata record.",
                changeLogAction: "sync_conflict_replaced",
                recoveryNote: "The previous fixture version remains recoverable."
            ) : nil
        )
    }

    private static func iCloudVersion(
        id: String,
        role: ICloudConflictVersionRoleSnapshot,
        path: String,
        hash: String
    ) -> ICloudConflictVersionMetadataSnapshot {
        ICloudConflictVersionMetadataSnapshot(
            versionID: id,
            role: role,
            path: path,
            modifiedAt: timestamp,
            sizeBytes: 48128,
            hashSha256: hash,
            previewSummary: DeveloperFileActionScenarioFixture.userContent("Quarterly report preview"),
            previewStatus: .available
        )
    }

    private static func syncFile(
        path: String,
        fileID: Int64,
        role: SyncConflictFileRoleSnapshot,
        hash: String,
        source: String
    ) -> SyncConflictAffectedFileSnapshot {
        SyncConflictAffectedFileSnapshot(
            path: path,
            fileID: fileID,
            role: role,
            sizeBytes: 48128,
            modifiedAt: timestamp,
            hashSha256: hash,
            sourcePlatform: source
        )
    }
}

actor DeveloperSyncConflictCoreFixture: CoreICloudConflictListing,
    CoreICloudConflictReviewing,
    CoreRepositoryPathValidating,
    ICloudConflictResolving,
    CoreSyncConflictDetecting,
    CoreSyncConflictResolving {
    nonisolated let iCloudConflictResolutionCapability = ICloudConflictResolutionCapability.supported

    func listICloudConflicts(repoPath _: String) async throws -> [ICloudConflictPairSnapshot] {
        [DeveloperSyncConflictScenarioFixture.iCloudPair]
    }

    func previewICloudConflict(
        repoPath _: String,
        conflictID _: String
    ) async throws -> ICloudConflictPreviewSnapshot {
        DeveloperSyncConflictScenarioFixture.iCloudPreview
    }

    func resolvePreviewedICloudConflict(
        _ request: ICloudConflictResolutionRequest
    ) async throws -> ICloudConflictResolutionResult {
        ICloudConflictResolutionResult(report: iCloudReport(request))
    }

    func resolveICloudConflict(
        _ request: ICloudConflictResolutionRequest
    ) async throws -> ICloudConflictResolutionResult {
        ICloudConflictResolutionResult(report: iCloudReport(request))
    }

    func validateRepoPath(repoPath _: String) async throws -> RepoPathValidationSnapshot {
        DeveloperSyncConflictScenarioFixture.pathValidation
    }

    func detectSyncConflicts(repoPath _: String) async throws -> [SyncConflictSnapshot] {
        [DeveloperSyncConflictScenarioFixture.syncConflict]
    }

    func previewSyncConflictResolution(
        repoPath _: String,
        conflictID _: String,
        resolution: SyncConflictResolutionStrategySnapshot
    ) async throws -> SyncConflictResolutionPreviewSnapshot {
        DeveloperSyncConflictScenarioFixture.syncPreview(resolution: resolution)
    }

    func resolveSyncConflict(
        repoPath _: String,
        conflictID: String,
        request: SyncConflictResolutionRequestSnapshot
    ) async throws -> SyncConflictResolveReportSnapshot {
        SyncConflictResolveReportSnapshot(
            conflictID: conflictID,
            resolution: request.strategy,
            status: .resolved,
            keptPaths: DeveloperSyncConflictScenarioFixture.syncConflict.affectedFiles.map(\.path),
            retainedPaths: DeveloperSyncConflictScenarioFixture.syncConflict.affectedFiles.map(\.path),
            trashedPaths: [],
            affectedFileIDs: DeveloperSyncConflictScenarioFixture.syncConflict.affectedFiles.compactMap(\.fileID),
            changeLogAction: "sync_conflict_resolved",
            undoToken: nil,
            resolvedAt: DeveloperSyncConflictScenarioFixture.timestamp
        )
    }

    private func iCloudReport(
        _ request: ICloudConflictResolutionRequest
    ) -> ICloudConflictResolveReportSnapshot {
        ICloudConflictResolveReportSnapshot(
            conflictID: request.conflictID,
            resolution: request.strategy,
            status: .resolved,
            keptPaths: [request.originalPath, request.conflictedCopyPath].compactMap { $0 },
            trashedPaths: [],
            undoToken: nil,
            changeLogAction: "icloud_conflict_resolved"
        )
    }
}

struct DeveloperSyncConflictPlatformActions: RepositoryFinderOpening, RepositoryFileRevealing {
    @MainActor
    func openRepositoryInFinder(repoPath _: String) throws {}

    @MainActor
    func revealFile(repoPath _: String, relativePath _: String) throws {}
}
#endif
