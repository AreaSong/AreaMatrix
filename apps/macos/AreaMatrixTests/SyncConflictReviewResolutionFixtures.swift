@testable import AreaMatrix

extension SyncConflictResolutionPreviewSnapshot {
    static func syncConflictReviewPreviewFixture(
        conflictID: String = "conflict-report",
        resolution: SyncConflictResolutionStrategySnapshot = .keepBoth,
        canApply: Bool = true,
        requiresReplaceConfirmation: Bool = false,
        trashAvailable: Bool = true,
        backupTarget: String? = "Trash",
        blockedReason: String? = nil,
        previewToken: String? = "preview-token-keep-both"
    ) -> SyncConflictResolutionPreviewSnapshot {
        SyncConflictResolutionPreviewSnapshot(
            conflictID: conflictID,
            resolution: resolution,
            defaultResolution: .keepBoth,
            statusAfter: .resolved,
            versionImpacts: [
                .syncConflictReviewImpactFixture(path: "docs/report.pdf", role: .existing, willBeCanonical: true),
                .syncConflictReviewImpactFixture(
                    path: "docs/report (Windows conflict).pdf",
                    fileID: 43,
                    role: .incoming,
                    willBeCanonical: resolution == .useIncoming
                )
            ],
            keptPaths: ["docs/report.pdf"],
            retainedPaths: resolution == .keepBoth ? ["docs/report (Windows conflict).pdf"] : [],
            plannedTrashPaths: resolution == .useIncoming ? ["docs/report.pdf"] : [],
            affectedFileIDs: [42, 43],
            canonicalPath: "docs/report.pdf",
            changeLogAction: changeLogAction(for: resolution),
            destructive: resolution == .useIncoming,
            requiresReplaceConfirmation: requiresReplaceConfirmation,
            trashRequired: resolution == .useIncoming,
            trashAvailable: trashAvailable,
            canApply: canApply,
            blockedReason: blockedReason,
            previewToken: previewToken,
            replacePlan: resolution == .useIncoming ? .syncConflictReviewReplacePlanFixture(
                backupTarget: backupTarget
            ) :
                nil
        )
    }

    static func changeLogAction(for resolution: SyncConflictResolutionStrategySnapshot) -> String {
        switch resolution {
        case .keepBoth:
            "conflict_resolved_keep_both"
        case .useExisting:
            "conflict_resolved_use_existing"
        case .useIncoming:
            "conflict_resolved_use_incoming"
        }
    }
}

extension SyncConflictVersionImpactSnapshot {
    static func syncConflictReviewImpactFixture(
        path: String,
        fileID: Int64 = 42,
        role: SyncConflictFileRoleSnapshot,
        willBeCanonical: Bool
    ) -> SyncConflictVersionImpactSnapshot {
        SyncConflictVersionImpactSnapshot(
            path: path,
            fileID: fileID,
            role: role,
            willKeep: true,
            willBeCanonical: willBeCanonical,
            willRemainUserVisible: true,
            willMoveToTrash: false,
            recoveryTarget: nil,
            reason: "Visible file is preserved by sync-conflict-resolve."
        )
    }
}

extension SyncConflictReplacePlanSnapshot {
    static func syncConflictReviewReplacePlanFixture(backupTarget: String? = "Trash")
        -> SyncConflictReplacePlanSnapshot {
        SyncConflictReplacePlanSnapshot(
            oldPath: "docs/report.pdf",
            newPath: "docs/report (Windows conflict).pdf",
            oldHashSha256: "abcdef1234567890",
            newHashSha256: "fedcba9876543210",
            affectedFileID: 42,
            backupTarget: backupTarget,
            databaseUpdate: "canonical record points to incoming",
            changeLogAction: "conflict_resolved_use_incoming",
            recoveryNote: "replace-resolution confirmation is required."
        )
    }
}

extension SyncConflictResolveReportSnapshot {
    static func syncConflictReviewResolveFixture(
        resolution: SyncConflictResolutionStrategySnapshot = .keepBoth
    ) -> SyncConflictResolveReportSnapshot {
        SyncConflictResolveReportSnapshot(
            conflictID: "conflict-report",
            resolution: resolution,
            status: .resolved,
            keptPaths: ["docs/report.pdf"],
            retainedPaths: ["docs/report (Windows conflict).pdf"],
            trashedPaths: resolution == .useIncoming ? ["docs/report.pdf"] : [],
            affectedFileIDs: [42, 43],
            changeLogAction: SyncConflictResolutionPreviewSnapshot.changeLogAction(for: resolution),
            undoToken: nil,
            resolvedAt: 1_778_738_500
        )
    }
}

extension SyncConflictSnapshot {
    static func syncConflictReviewFixture(
        conflictID: String = "conflict-report",
        status: SyncConflictStatusSnapshot = .needsReview,
        primaryPath: String = "docs/report.pdf"
    ) -> SyncConflictSnapshot {
        SyncConflictSnapshot(
            conflictID: conflictID,
            conflictType: .sameNameDifferentContent,
            severity: .high,
            status: status,
            primaryPath: primaryPath,
            affectedFiles: [
                .syncConflictReviewFileFixture(path: primaryPath, role: .existing),
                .syncConflictReviewFileFixture(
                    path: primaryPath == "docs/report.pdf"
                        ? "docs/report (Windows conflict).pdf"
                        : "docs/other (Windows conflict).pdf",
                    fileID: 43,
                    role: .incoming,
                    hashSha256: "fedcba9876543210",
                    sourcePlatform: "Windows"
                )
            ],
            versionCount: 2,
            sourceProvider: "OneDrive",
            detectedAt: 1_778_738_400,
            summary: "Two versions of docs/report.pdf need review."
        )
    }
}

extension RepositoryOpeningResult {
    static func syncConflictReviewFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: RepoConfigSnapshot(
                repoPath: repoPath,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "zh-Hans",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "Repository",
                kind: "RepositoryRoot",
                relativePath: "",
                fileCount: Int64(files.count),
                depth: 0,
                children: []
            ),
            currentCategoryFiles: files
        )
    }
}

extension FileEntrySnapshot {
    static func syncConflictReviewFixture(id: Int64, path: String, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 2048,
            hashSha256: "syncConflictReview-file-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_778_738_300,
            updatedAt: 1_778_738_400
        )
    }
}

extension SyncConflictAffectedFileSnapshot {
    static func syncConflictReviewFileFixture(
        path: String = "docs/report.pdf",
        fileID: Int64? = 42,
        role: SyncConflictFileRoleSnapshot = .existing,
        hashSha256: String? = "abcdef1234567890",
        sourcePlatform: String? = "macOS"
    ) -> SyncConflictAffectedFileSnapshot {
        SyncConflictAffectedFileSnapshot(
            path: path,
            fileID: fileID,
            role: role,
            sizeBytes: 2048,
            modifiedAt: 1_778_738_400,
            hashSha256: hashSha256,
            sourcePlatform: sourcePlatform
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func syncConflictReviewMapping(
        kind: CoreErrorKindSnapshot = .conflict,
        rawContext: String = "/tmp/syncConflictReview-repo"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "AreaMatrix cannot inspect this sync conflict.",
            severity: .high,
            suggestedAction: "Refresh the conflict list or retry after sync finishes.",
            recoverability: .refreshRequired,
            rawContext: rawContext
        )
    }
}
