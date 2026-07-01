@testable import AreaMatrix
import Foundation

func makeRepairTemporaryAdoptRepoURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixAdoptExisting")
}

typealias RepairRecordingSettingsWriter = RecordingAppSettingsWriter

typealias RepairRecordingRepositoryOpener = RecordingRepositoryOpener

typealias RepairRecordingPathValidator = RecordingRepositoryPathValidator

typealias RepairSequencePathValidator = RecordingRepositoryPathValidator

typealias RepairRecordingRepositoryInitializer = RecordingRepositoryInitializer

typealias RepairPausingRepositoryInitializer = PausingRepositoryInitializer

typealias RepairExistingRepoMetadataReader = StaticExistingRepositoryMetadataReader

extension RepoConfigSnapshot {
    static func repairFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot(
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
        )
    }
}

extension RepositoryOpeningResult {
    static func repairFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .repairFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(
                slug: "__root__",
                displayName: "资料库",
                fileCount: fileCount,
                children: []
            ),
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
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: isEmpty,
            isInitialized: isInitialized,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: availableCapacityBytes,
            isExternalVolume: isExternalVolume,
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}
