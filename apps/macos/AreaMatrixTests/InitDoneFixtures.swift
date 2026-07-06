@testable import AreaMatrix

extension RepoConfigSnapshot {
    static func initDoneFixture(repoPath: String) -> RepoConfigSnapshot {
        RepoConfigSnapshot.testFixture(repoPath: repoPath)
    }
}

extension RepositoryOpeningResult {
    static func initDoneFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .initDoneFixture(repoPath: repoPath),
            tree: .testRoot(displayName: "资料库", fileCount: fileCount),
            currentCategoryFiles: []
        )
    }
}

extension FileEntrySnapshot {
    static func initDoneFileFixture(category: String) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: 1,
            path: "\(category)/report.pdf",
            currentName: "report.pdf",
            category: category
        ) {
            $0.hashSha256 = "fixture-hash"
            $0.updatedAt = 1_700_000_000
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func initDoneConfigFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .config,
            userMessage: "资料库配置不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }

    static func initDoneDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "资料库树不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

extension ScanSessionSnapshot {
    static func adoptCompletedFixture() -> ScanSessionSnapshot {
        ScanSessionSnapshot.testFixture(status: .completed) {
            $0.lastPath = "README.md"
            $0.inserted = 1
            $0.updated = 0
            $0.skipped = 0
            $0.updatedAt = 1_700_000_001
            $0.finishedAt = 1_700_000_001
        }
    }
}
