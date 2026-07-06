@testable import AreaMatrix

extension RepoConfigSnapshot {
    static func smokeFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepositoryOpeningResult {
    static func smokeFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .smokeFixture(repoPath: repoPath),
            tree: .testRoot(displayName: "资料库", fileCount: fileCount),
            currentCategoryFiles: []
        )
    }
}

extension RepoPathValidationSnapshot {
    static func smokeAdoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        smokeFixture(
            repoPath: repoPath,
            isEmpty: false,
            issues: [.nonEmptyDirectory],
            recommendedMode: .adoptExisting
        )
    }

    static func smokeFixture(
        repoPath: String,
        isEmpty: Bool = true,
        isInitialized: Bool = false,
        hasUnfinishedScanSession: Bool = false,
        availableCapacityBytes: Int64? = 1_073_741_824,
        isExternalVolume: Bool? = false,
        issues: [RepoPathIssueSnapshot] = [],
        recommendedMode: RepoInitModeSnapshot? = .createEmpty
    ) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.testFixture(repoPath: repoPath) {
            $0.isEmpty = isEmpty
            $0.isInitialized = isInitialized
            $0.hasUnfinishedScanSession = hasUnfinishedScanSession
            $0.availableCapacityBytes = availableCapacityBytes
            $0.isExternalVolume = isExternalVolume
            $0.recommendedMode = recommendedMode
            $0.issues = issues
        }
    }
}

extension ScanSessionSnapshot {
    static func adoptFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot.testFixture(id: 7, status: .interrupted) {
            $0.lastPath = "docs/report.pdf"
            $0.updated = 1
            $0.skipped = 3
            $0.updatedAt = 1_700_000_120
        }
    }
}
