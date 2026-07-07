@testable import AreaMatrix

extension FileEntrySnapshot {
    static func changeCategoryFixture(
        id: Int64,
        path: String = "docs/contracts/contract.pdf",
        category: String = "docs",
        name: String,
        updatedAt: Int64 = 1_700_000_100
    ) -> FileEntrySnapshot {
        FileEntrySnapshot.testFixture(
            id: id,
            path: path,
            currentName: name,
            category: category
        ) {
            $0.sizeBytes = 512
            $0.hashSha256 = "change-category-\(id)"
            $0.updatedAt = updatedAt
        }
    }
}

extension RepositoryTreeNodeSnapshot {
    static func changeCategoryTree(docsCount: Int64, financeCount: Int64) -> RepositoryTreeNodeSnapshot {
        .testRoot(
            children: [
                .testCategory("docs", fileCount: docsCount),
                .testCategory("finance", fileCount: financeCount)
            ]
        )
    }
}

extension MoveToCategoryPreviewSnapshot {
    static func testFixture(
        fileID: Int64,
        fromCategory: String = "docs",
        toCategory: String = "finance",
        targetName: String = "contract.pdf",
        configure: (inout MoveToCategoryPreviewSnapshot) -> Void = { _ in }
    ) -> MoveToCategoryPreviewSnapshot {
        var snapshot = MoveToCategoryPreviewSnapshot(
            fileID: fileID,
            fromCategory: fromCategory,
            toCategory: toCategory,
            currentPath: "\(fromCategory)/\(targetName)",
            targetPath: "\(toCategory)/\(targetName)",
            targetName: targetName,
            storageMode: "Copied",
            indexOnly: false,
            nameConflictResolved: false,
            willMoveFile: true
        )
        configure(&snapshot)
        return snapshot
    }

    static func changeCategoryFixture(
        fileID: Int64,
        targetPath: String,
        targetName: String,
        indexOnly: Bool = false,
        nameConflictResolved: Bool = false
    ) -> MoveToCategoryPreviewSnapshot {
        MoveToCategoryPreviewSnapshot.testFixture(
            fileID: fileID,
            targetName: targetName
        ) {
            $0.currentPath = "docs/contracts/\(targetName)"
            $0.targetPath = targetPath
            $0.storageMode = indexOnly ? "Indexed" : "Copied"
            $0.indexOnly = indexOnly
            $0.nameConflictResolved = nameConflictResolved
            $0.willMoveFile = !indexOnly
        }
    }
}

extension ClassifierCorrectionResultSnapshot {
    static func testFixture(
        updatedFile: FileEntrySnapshot,
        ruleDraft: ClassifierRuleDraftSnapshot? = .testFixture(),
        moveFileRequested: Bool = true,
        rememberRequested: Bool = true,
        ruleConfirmationRequired: Bool = true
    ) -> ClassifierCorrectionResultSnapshot {
        ClassifierCorrectionResultSnapshot(
            updatedFile: updatedFile,
            ruleDraft: ruleDraft,
            moveFileRequested: moveFileRequested,
            rememberRequested: rememberRequested,
            ruleConfirmationRequired: ruleConfirmationRequired
        )
    }
}

func changeCategoryPredictionFixture() -> ClassifyResultSnapshot {
    .testFixture(
        category: "docs",
        suggestedName: "contract.pdf",
        reason: .extension,
        confidence: 0.93
    )
}

extension CoreErrorMappingSnapshot {
    static func changeCategoryClassify() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .classify,
            userMessage: "Target category is unavailable.",
            severity: .medium,
            suggestedAction: "Choose another category, then retry.",
            recoverability: .userActionRequired,
            rawContext: "change-category move-to-category preview_move_to_category"
        )
    }

    static func changeCategoryConflict() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .conflict,
            userMessage: "Path conflict.",
            severity: .medium,
            suggestedAction: "Rename the file first, then retry.",
            recoverability: .userActionRequired,
            rawContext: "change-category resolve-name-conflict safe target name"
        )
    }

    static func changeCategoryPermissionDenied() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .permissionDenied,
            userMessage: "Target category is not writable.",
            severity: .high,
            suggestedAction: "Grant folder access in Finder, then retry.",
            recoverability: .userActionRequired,
            rawContext: "change-category move-to-category preview_move_to_category permission"
        )
    }
}
