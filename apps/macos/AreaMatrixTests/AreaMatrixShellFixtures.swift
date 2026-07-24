@testable import AreaMatrix

extension AppRepoConfigSnapshot {
    static func shellFixture(repoPath: String) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepositoryOpeningResult {
    static func shellFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .shellFixture(repoPath: repoPath),
            tree: .testRoot(displayName: "资料库", fileCount: fileCount),
            currentCategoryFiles: []
        )
    }
}

extension SyncResultSnapshot {
    static func shellDeletedFixture() -> SyncResultSnapshot {
        .deletedFixture()
    }

    static func shellRenamedFixture() -> SyncResultSnapshot {
        .renamedFixture()
    }
}

extension RepoPathValidationSnapshot {
    static func shellFixture(
        repoPath: String,
        exists: Bool = true,
        isDirectory: Bool = true,
        isReadable: Bool = true,
        isWritable: Bool = true,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        isICloudPath: Bool = false,
        hasUnfinishedScanSession: Bool = false,
        availableCapacityBytes: Int64? = 1_073_741_824,
        isExternalVolume: Bool? = false,
        issues: [RepoPathIssueSnapshot] = [],
        recommendedMode: RepoInitModeSnapshot? = .createEmpty
    ) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.testFixture(repoPath: repoPath) {
            $0.exists = exists
            $0.isDirectory = isDirectory
            $0.isReadable = isReadable
            $0.isWritable = isWritable
            $0.isEmpty = isEmpty
            $0.isInitialized = isInitialized
            $0.isICloudPath = isICloudPath
            $0.hasUnfinishedScanSession = hasUnfinishedScanSession
            $0.availableCapacityBytes = availableCapacityBytes
            $0.isExternalVolume = isExternalVolume
            $0.recommendedMode = recommendedMode
            $0.issues = issues
        }
    }
}
