@testable import AreaMatrix

extension SyncResultSnapshot {
    static func iCloudConflictMinimalEmptySyncResult() -> SyncResultSnapshot {
        .testFixture()
    }
}

extension MainDetailLogState {
    var iCloudConflictMinimalLoadedFileID: Int64? {
        guard case let .loaded(fileID, _) = self else { return nil }
        return fileID
    }
}

extension ChangeLogEntrySnapshot {
    static func iCloudConflictMinimalConflictResolved(fileID: Int64?) -> ChangeLogEntrySnapshot {
        ChangeLogEntrySnapshot.testFixture(
            id: 1,
            fileID: fileID,
            filename: "report (Conflicted Copy).pdf",
            category: "docs",
            action: "conflict_resolved_keep_both",
            detailJSON: #"{"conflict_id":"iCloudConflictMinimal","kept_paths":["docs/report.pdf","# +
                #""docs/report (Conflicted Copy).pdf"]}"#,
            occurredAt: 1_775_020_900
        )
    }
}

extension RepositoryOpeningResult {
    static func iCloudConflictMinimalFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: .testRoot(
                displayName: "资料库",
                fileCount: Int64(files.count),
                children: [
                    .testCategory("docs", fileCount: Int64(files.count))
                ]
            ),
            currentCategoryFiles: files
        )
    }
}

extension FileEntrySnapshot {
    static func iCloudConflictMinimalConflictFixture(id: Int64) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/report (Conflicted Copy).pdf",
            currentName: "report (Conflicted Copy).pdf",
            category: "docs"
        ) {
            $0.sizeBytes = 512
            $0.hashSha256 = "iCloudConflictMinimal-conflict-\(id)"
            $0.updatedAt = 1_775_020_860
        }
    }
}

extension RepoPathValidationSnapshot {
    static func iCloudConflictMinimalICloudConflictFixture() -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/iCloudConflictMinimal-repo",
            isEmpty: false,
            isInitialized: true,
            isICloudPath: true,
            issues: [.alreadyInitialized, .iCloudPath],
            recommendedMode: nil
        )
    }
}

extension ICloudConflictVersionSnapshot {
    static func testFixture(
        role: ICloudConflictVersionSnapshot.Role,
        path: String,
        modifiedAt: Int64 = 1_775_020_800,
        sizeBytes: Int64 = 512
    ) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: role,
            path: path,
            modifiedAt: modifiedAt,
            sizeBytes: sizeBytes
        )
    }

    static func iCloudConflictMinimalOriginal(repoPath: String) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot.testFixture(
            role: .original,
            path: "\(repoPath)/docs/report.pdf",
            sizeBytes: 512
        )
    }

    static func iCloudConflictMinimalConflictedCopy(repoPath: String) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot.testFixture(
            role: .conflictedCopy,
            path: "\(repoPath)/docs/report (Conflicted Copy).pdf",
            modifiedAt: 1_775_020_860,
            sizeBytes: 768
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func iCloudConflictMinimalMapping(
        kind: CoreErrorKindSnapshot = .iCloudPlaceholder,
        rawContext: String = "/tmp/iCloudConflictMinimal-repo/docs/report.pdf.icloud"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: kind,
            userMessage: "AreaMatrix cannot inspect this conflict source.",
            severity: .high,
            suggestedAction: "Refresh the source page or download the iCloud item in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }
}

extension ICloudConflictPreviewSnapshot {
    // swiftlint:disable:next function_body_length
    static func iCloudConflictVisualPreview(
        conflictID: String,
        metadataComplete: Bool = true,
        trashAvailable: Bool = true
    ) -> ICloudConflictPreviewSnapshot {
        ICloudConflictPreviewSnapshot(
            conflictID: conflictID,
            versions: [
                ICloudConflictVersionMetadataSnapshot(
                    versionID: "original",
                    role: .original,
                    path: "docs/report.pdf",
                    modifiedAt: 1_775_020_800,
                    sizeBytes: 512,
                    hashSha256: "aaaaaaaaaaaabbbb",
                    previewSummary: "Original preview",
                    previewStatus: .available
                ),
                ICloudConflictVersionMetadataSnapshot(
                    versionID: "conflicted-copy",
                    role: .conflictedCopy,
                    path: "docs/report (copy).pdf",
                    modifiedAt: 1_775_020_860,
                    sizeBytes: 768,
                    hashSha256: "bbbbbbbbbbbbaaaa",
                    previewSummary: "Conflicted preview",
                    previewStatus: .available
                )
            ],
            defaultResolution: .keepBoth,
            resolutionOptions: [
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepBoth,
                    destructive: false,
                    requiresTrash: false,
                    enabled: true,
                    disabledReason: nil
                ),
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepOriginalOnly,
                    destructive: true,
                    requiresTrash: true,
                    enabled: metadataComplete && trashAvailable,
                    disabledReason: metadataComplete && trashAvailable ? nil : "Trash unavailable"
                ),
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepConflictedCopyOnly,
                    destructive: true,
                    requiresTrash: true,
                    enabled: metadataComplete && trashAvailable,
                    disabledReason: metadataComplete && trashAvailable ? nil : "Trash unavailable"
                )
            ],
            metadataComplete: metadataComplete,
            trashAvailable: trashAvailable,
            canKeepBoth: true,
            canResolveDestructive: metadataComplete && trashAvailable,
            blockedReason: metadataComplete && trashAvailable ? nil : "Trash unavailable"
        )
    }
}

extension ICloudConflictResolveReportSnapshot {
    static func iCloudConflictVisualResolvedReport(conflictID: String) -> ICloudConflictResolveReportSnapshot {
        ICloudConflictResolveReportSnapshot(
            conflictID: conflictID,
            resolution: .keepBoth,
            status: .resolved,
            keptPaths: [
                "docs/report.pdf",
                "docs/report (copy).pdf"
            ],
            trashedPaths: [],
            undoToken: nil,
            changeLogAction: "external_modified"
        )
    }
}
