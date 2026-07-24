@testable import AreaMatrix

extension AppRepoConfigSnapshot {
    static func repairFixture(repoPath: String) -> AppRepoConfigSnapshot {
        AppRepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepositoryOpeningResult {
    static func repairFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .repairFixture(repoPath: repoPath),
            tree: .testRoot(displayName: "资料库", fileCount: fileCount),
            currentCategoryFiles: []
        )
    }
}

extension RepoPathValidationSnapshot {
    static func repairFixture(
        repoPath: String,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        availableCapacityBytes: Int64? = 1_073_741_824,
        isExternalVolume: Bool? = false,
        issues: [RepoPathIssueSnapshot] = [],
        recommendedMode: RepoInitModeSnapshot? = .createEmpty
    ) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.testFixture(repoPath: repoPath) {
            $0.isEmpty = isEmpty
            $0.isInitialized = isInitialized
            $0.availableCapacityBytes = availableCapacityBytes
            $0.isExternalVolume = isExternalVolume
            $0.recommendedMode = recommendedMode
            $0.issues = issues
        }
    }
}
