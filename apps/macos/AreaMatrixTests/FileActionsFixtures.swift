@testable import AreaMatrix
import Foundation

extension RepositoryOpeningResult {
    static func fileActionsFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
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
            tree: .fileActionsTree(docsCount: Int64(files.count), financeCount: 0),
            currentCategoryFiles: files
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func fileActionsTree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: docsCount, children: []),
                RepositoryTreeNodeSnapshot(
                    slug: "finance",
                    displayName: "finance",
                    fileCount: financeCount,
                    children: []
                )
            ]
        )
    }
}

extension FileEntrySnapshot {
    static func fileActionsFixture(id: Int64, name: String, storageMode: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(name)",
            originalName: name,
            currentName: name,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "file-actions-\(id)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}
