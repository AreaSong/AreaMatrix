@testable import AreaMatrix
import Foundation

func makeInitDoneTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixInitDoneTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

extension RepoConfigSnapshot {
    static func initDoneFixture(repoPath: String) -> RepoConfigSnapshot {
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
    static func initDoneFixture(repoPath: String, fileCount: Int64) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .initDoneFixture(repoPath: repoPath),
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

extension FileEntrySnapshot {
    static func initDoneFileFixture(category: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 1,
            path: "\(category)/report.pdf",
            originalName: "report.pdf",
            currentName: "report.pdf",
            category: category,
            sizeBytes: 128,
            hashSha256: "fixture-hash",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_000
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func initDoneConfigFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "资料库配置不可用",
            severity: .high,
            suggestedAction: "请重试打开资料库，或重新选择资料库位置。",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }

    static func initDoneDbFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
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
        ScanSessionSnapshot(
            id: 42,
            kind: .adopt,
            status: .completed,
            lastPath: "README.md",
            inserted: 1,
            updated: 0,
            skipped: 0,
            startedAt: 1_700_000_000,
            updatedAt: 1_700_000_001,
            finishedAt: 1_700_000_001,
            errors: []
        )
    }
}
