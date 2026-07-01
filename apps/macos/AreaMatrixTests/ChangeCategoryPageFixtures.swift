@testable import AreaMatrix

extension FileEntrySnapshot {
    static func changeCategoryFixture(
        id: Int64,
        path: String = "docs/contracts/contract.pdf",
        category: String = "docs",
        name: String,
        updatedAt: Int64 = 1_700_000_100
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: name,
            currentName: name,
            category: category,
            sizeBytes: 512,
            hashSha256: "change-category-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: updatedAt
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func changeCategoryTree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
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

extension MoveToCategoryPreviewSnapshot {
    static func changeCategoryFixture(
        fileID: Int64,
        targetPath: String,
        targetName: String,
        indexOnly: Bool = false,
        nameConflictResolved: Bool = false
    ) -> MoveToCategoryPreviewSnapshot {
        MoveToCategoryPreviewSnapshot(
            fileID: fileID,
            fromCategory: "docs",
            toCategory: "finance",
            currentPath: "docs/contracts/\(targetName)",
            targetPath: targetPath,
            targetName: targetName,
            storageMode: indexOnly ? "Indexed" : "Copied",
            indexOnly: indexOnly,
            nameConflictResolved: nameConflictResolved,
            willMoveFile: !indexOnly
        )
    }
}

extension CoreErrorMappingSnapshot {
    static func changeCategoryClassify() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .classify,
            userMessage: "Target category is unavailable.",
            severity: .medium,
            suggestedAction: "Choose another category, then retry.",
            recoverability: .userActionRequired,
            rawContext: "change-category move-to-category preview_move_to_category"
        )
    }
}
