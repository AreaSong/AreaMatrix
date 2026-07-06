@testable import AreaMatrix
import Foundation

extension RepositoryOpeningResult {
    static func fileActionsFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .testFixture(repoPath: repoPath),
            tree: .fileActionsTree(docsCount: Int64(files.count), financeCount: 0),
            currentCategoryFiles: files
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func fileActionsTree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot.testRoot(children: [
            .testCategory("docs", fileCount: docsCount),
            .testCategory("finance", fileCount: financeCount)
        ])
    }
}

extension FileEntrySnapshot {
    static func fileActionsFixture(id: Int64, name: String, storageMode: String) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/\(name)",
            currentName: name,
            category: "docs"
        ) {
            $0.hashSha256 = "file-actions-\(id)"
            $0.storageMode = storageMode
        }
    }
}
