@testable import AreaMatrix
import Foundation

extension RepositoryOpeningResult {
    static func mainLoadingFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .mainLoadingFixture(repoPath: repoPath),
            tree: RepositoryTreeNodeSnapshot(slug: "__root__", displayName: "资料库", fileCount: fileCount, children: []),
            currentCategoryFiles: []
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func mainLoadingTreeFixture() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "资料库",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [.mainLoadingDocsFixture()]
        )
    }

    private static func mainLoadingDocsFixture() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "docs",
            displayName: "docs",
            kind: "SystemCategory",
            relativePath: "docs",
            fileCount: 1,
            depth: 1,
            children: [.mainLoadingContractsFixture()]
        )
    }

    private static func mainLoadingContractsFixture() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "contracts",
            displayName: "contracts",
            kind: "Folder",
            relativePath: "docs/contracts",
            fileCount: 1,
            depth: 2,
            children: []
        )
    }
}

extension RepoConfigSnapshot {
    static func mainLoadingFixture(repoPath: String) -> RepoConfigSnapshot {
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

    static func initializingFixture(repoPath: String) -> RepoConfigSnapshot {
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

extension RepoPathValidationSnapshot {
    static func mainLoadingInitializedFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: true,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: 1_073_741_824,
            isExternalVolume: false,
            recommendedMode: nil,
            issues: [.alreadyInitialized]
        )
    }

    static func initializingAdoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: false,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: false,
            availableCapacityBytes: 1_073_741_824,
            isExternalVolume: false,
            recommendedMode: .adoptExisting,
            issues: [.nonEmptyDirectory]
        )
    }
}

extension ScanSessionSnapshot {
    static func mainLoadingAdoptFixture(status: ScanSessionStatusSnapshot) -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: status,
            lastPath: "docs/plan.md",
            inserted: 12,
            updated: 2,
            skipped: 1,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_010,
            finishedAt: nil,
            errors: []
        )
    }

    static func mainLoadingReindexFixture(
        status: ScanSessionStatusSnapshot,
        errors: [String] = []
    ) -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 84,
            kind: .reindex,
            status: status,
            lastPath: "docs/contracts/customer.pdf",
            inserted: 300,
            updated: 20,
            skipped: 4,
            startedAt: 1_700_000_100,
            updatedAt: 1_700_000_140,
            finishedAt: nil,
            errors: errors
        )
    }

    static func adoptRunningFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: .running,
            lastPath: "docs/plan.md",
            inserted: 11,
            updated: 2,
            skipped: 1,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_010,
            finishedAt: nil,
            errors: ["skipped unreadable file: private.tmp"]
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func mainLoadingDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "扫描状态暂不可用",
            severity: .medium,
            suggestedAction: "资料库打开后可重试扫描状态读取。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }

    static func initializingPermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func initializingDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "数据库错误",
            severity: .critical,
            suggestedAction: "请检查资料库 metadata 后重试",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }
}

func makeMainLoadingTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixMainLoadingTreeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
