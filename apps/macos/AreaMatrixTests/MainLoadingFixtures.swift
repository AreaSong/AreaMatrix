@testable import AreaMatrix
import Foundation

func mainLoadingRepoPath() -> String {
    "/tmp/repo"
}

extension RepositoryOpeningResult {
    static func mainLoadingFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .mainLoadingFixture(repoPath: repoPath),
            tree: .testRoot(displayName: "资料库", fileCount: fileCount),
            currentCategoryFiles: []
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func mainLoadingTreeFixture() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot.testRoot(displayName: "资料库", children: [.mainLoadingDocsFixture()])
    }

    private static func mainLoadingDocsFixture() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot.testCategory("docs", fileCount: 1, children: [.mainLoadingContractsFixture()])
    }

    private static func mainLoadingContractsFixture() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot.testSubdirectory(
            "contracts",
            relativePath: "docs/contracts",
            fileCount: 1,
            kind: "Folder"
        )
    }
}

extension RepoConfigSnapshot {
    static func mainLoadingFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath)
    }

    static func initializingFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepoPathValidationSnapshot {
    static func mainLoadingInitializedFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.testFixture(repoPath: repoPath) {
            $0.isEmpty = false
            $0.isInitialized = true
            $0.recommendedMode = nil
            $0.issues = [.alreadyInitialized]
        }
    }

    static func initializingAdoptExistingFixture(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot.testFixture(repoPath: repoPath) {
            $0.isEmpty = false
            $0.recommendedMode = .adoptExisting
            $0.issues = [.nonEmptyDirectory]
        }
    }
}

extension ScanSessionSnapshot {
    static func mainLoadingAdoptFixture(status: ScanSessionStatusSnapshot) -> ScanSessionSnapshot {
        ScanSessionSnapshot.testFixture(status: status)
    }

    static func mainLoadingReindexFixture(
        status: ScanSessionStatusSnapshot,
        errors: [String] = []
    ) -> ScanSessionSnapshot {
        ScanSessionSnapshot.testFixture(id: 84, kind: .reindex, status: status) {
            $0.lastPath = "docs/contracts/customer.pdf"
            $0.inserted = 300
            $0.updated = 20
            $0.skipped = 4
            $0.startedAt = 1_700_000_100
            $0.updatedAt = 1_700_000_140
            $0.errors = errors
        }
    }

    static func adoptRunningFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot.testFixture(status: .running) {
            $0.inserted = 11
            $0.errors = ["skipped unreadable file: private.tmp"]
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func mainLoadingDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "扫描状态暂不可用",
            suggestedAction: "资料库打开后可重试扫描状态读取。",
            rawContext: rawContext
        )
    }

    static func initializingPermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func initializingDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "数据库错误",
            severity: .critical,
            suggestedAction: "请检查资料库 metadata 后重试",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }
}
