import Foundation

#if DEBUG
enum DeveloperFileActionScenarioFixture {
    static let repoPath = AreaMatrixPreviewFixtures.repositoryPath
    static let timestamp: Int64 = 1_778_738_400

    static var primaryFile: FileEntrySnapshot {
        file(
            id: 1201,
            path: "docs/reports/quarterly-report.pdf",
            name: "quarterly-report.pdf",
            category: "docs",
            storageMode: "Copied"
        )
    }

    static var invoiceFile: FileEntrySnapshot {
        file(
            id: 1202,
            path: "finance/invoices/invoice-2026.pdf",
            name: "invoice-2026.pdf",
            category: "finance",
            storageMode: "Copied"
        )
    }

    static var indexedFile: FileEntrySnapshot {
        file(
            id: 1203,
            path: "docs/references/vendor-contract.pdf",
            name: "vendor-contract.pdf",
            category: "docs",
            storageMode: "Indexed",
            origin: "External"
        )
    }

    static var selectedFiles: [FileEntrySnapshot] {
        [primaryFile, invoiceFile, indexedFile]
    }

    static var categoryRows: [RepositorySidebarRowSnapshot] {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: userContent("AreaMatrix Developer Repository"),
            kind: "Root",
            fileCount: 0,
            depth: 0,
            children: [
                categoryNode(slug: "docs", displayName: "Documents", fileCount: 2),
                categoryNode(slug: "finance", displayName: "Finance", fileCount: 1),
                categoryNode(slug: "inbox", displayName: "Inbox", fileCount: 0)
            ]
        ).sidebarRows
    }

    static var tagSet: TagSetSnapshot {
        TagSetSnapshot(
            fileID: primaryFile.id,
            fileTags: [tag(value: "quarterly", label: userContent("Quarterly"), fileCount: 4, selected: true)],
            availableTags: [
                tag(value: "review", label: userContent("Review"), fileCount: 8),
                tag(value: "finance", label: userContent("Finance"), fileCount: 12),
                tag(value: "quarterly", label: userContent("Quarterly"), fileCount: 4, selected: true)
            ],
            recentTags: [
                tag(value: "review", label: userContent("Review"), fileCount: 8),
                tag(value: "finance", label: userContent("Finance"), fileCount: 12)
            ],
            updatedAt: timestamp
        )
    }

    static var tagSuggestionReport: TagSuggestionReportSnapshot {
        TagSuggestionReportSnapshot(
            fileID: primaryFile.id,
            suggestions: [
                TagSuggestionSnapshot(
                    suggestionID: "developer-tag-review",
                    slug: "review",
                    displayName: userContent("Review"),
                    reason: technicalDetail("Matched the report filename and repository path."),
                    source: .fileName,
                    matchStrength: .strong,
                    alreadyExists: true,
                    needsCreate: false,
                    status: .newTag,
                    selectedByDefault: true,
                    disabledReason: nil
                ),
                TagSuggestionSnapshot(
                    suggestionID: "developer-tag-quarterly-report",
                    slug: "quarterly-report",
                    displayName: userContent("Quarterly report"),
                    reason: technicalDetail("Matched recurring report naming patterns."),
                    source: .path,
                    matchStrength: .weak,
                    alreadyExists: false,
                    needsCreate: true,
                    status: .newTag,
                    selectedByDefault: false,
                    disabledReason: nil
                )
            ],
            tagSet: tagSet,
            contentsRead: false,
            aiUsed: false,
            networkUsed: false
        )
    }

    static var tagSuggestionState: DetailTagSuggestionState {
        let report = tagSuggestionReport
        return .loaded(
            fileID: report.fileID,
            report,
            Set(report.suggestions.filter(\.selectedByDefault).map(\.suggestionID))
        )
    }

    static var tagApplyReport: TagSuggestionApplyReportSnapshot {
        TagSuggestionApplyReportSnapshot(
            fileID: primaryFile.id,
            requestedCount: 1,
            appliedCount: 1,
            skippedCount: 0,
            failedCount: 0,
            itemResults: [
                TagSuggestionApplyItemResultSnapshot(
                    suggestionID: "developer-tag-review",
                    slug: "review",
                    status: .applied,
                    error: nil
                )
            ],
            tagSet: tagSet,
            undoToken: "developer-undo-tag-suggestion",
            refreshTargets: ["files", "tags", "undo_actions"]
        )
    }

    static var replaceContext: SingleFileReplaceConfirmationContext {
        SingleFileReplaceConfirmationContext(
            existingPath: filesystemPath("finance/invoices/invoice-2026.pdf"),
            existingSizeBytes: 48312,
            existingModifiedAt: timestamp - 3600,
            incomingPath: filesystemPath("/Users/example/Downloads/invoice-2026.pdf"),
            incomingSizeBytes: 51204,
            incomingModifiedAt: timestamp,
            targetRelativePath: filesystemPath("finance/invoices/invoice-2026.pdf"),
            isTrashAvailable: true
        )
    }

    static var classifierHandoff: ClassifierRuleHandoff {
        ClassifierRuleHandoff(
            sourcePageID: "classifier-correction",
            fileID: primaryFile.id,
            fileName: primaryFile.currentName,
            sourcePath: primaryFile.path,
            currentCategory: primaryFile.category,
            targetCategory: "finance",
            moveFile: true,
            draft: ClassifierRuleDraftSnapshot(
                sourceFileID: primaryFile.id,
                targetCategory: "finance",
                keywordCandidates: ["quarterly", "report"],
                extensionCandidates: ["pdf"],
                priority: 25
            ),
            selectedKeywords: ["quarterly"],
            selectedExtensions: ["pdf"],
            previewConfirmed: true
        )
    }

    static func movePreview(file: FileEntrySnapshot, targetCategory: String) -> MoveToCategoryPreviewSnapshot {
        let targetPath = filesystemPath("\(targetCategory)/\(file.currentName)")
        return MoveToCategoryPreviewSnapshot(
            fileID: file.id,
            fromCategory: file.category,
            toCategory: targetCategory,
            currentPath: file.path,
            targetPath: targetPath,
            targetName: file.currentName,
            storageMode: file.storageMode,
            indexOnly: file.storageMode == "Indexed",
            nameConflictResolved: false,
            willMoveFile: file.storageMode != "Indexed"
        )
    }

    static var undoActions: [UndoActionRecordSnapshot] {
        [
            UndoActionRecordSnapshot(
                actionID: "developer-undo-tags",
                kind: "batch_add_tags",
                summary: technicalDetail("Added Review to 3 files."),
                affectedCount: 3,
                affectedFileNames: selectedFiles.map(\.currentName),
                status: .pending,
                canUndo: true,
                disabledReason: nil,
                createdAt: timestamp,
                updatedAt: timestamp
            ),
            UndoActionRecordSnapshot(
                actionID: "developer-undo-rename",
                kind: "rename_files",
                summary: technicalDetail("Renamed 2 report files."),
                affectedCount: 2,
                affectedFileNames: [primaryFile.currentName, invoiceFile.currentName],
                status: .blocked,
                canUndo: false,
                disabledReason: technicalDetail("A later external change prevents this undo."),
                createdAt: timestamp - 120,
                updatedAt: timestamp - 60
            ),
            UndoActionRecordSnapshot(
                actionID: "developer-undo-source",
                kind: "move_files",
                summary: technicalDetail("Moved a report to Finance."),
                affectedCount: 1,
                affectedFileNames: [primaryFile.currentName],
                status: .executed,
                canUndo: false,
                disabledReason: nil,
                createdAt: timestamp - 240,
                updatedAt: timestamp - 180
            )
        ]
    }

    static var redoActions: [RedoActionRecordSnapshot] {
        [
            RedoActionRecordSnapshot(
                actionID: "developer-redo-move",
                kind: "move_files",
                summary: technicalDetail("Redo moving the report to Finance."),
                affectedCount: 1,
                affectedFileNames: [primaryFile.currentName],
                status: .available,
                canRedo: true,
                disabledReason: nil,
                sourceUndoActionID: "developer-undo-source",
                createdAt: timestamp - 180,
                updatedAt: timestamp - 180
            )
        ]
    }

    static func file(id: Int64) -> FileEntrySnapshot {
        selectedFiles.first { $0.id == id } ?? primaryFile
    }

    static func userContent(_ value: String) -> String {
        L10n.resolve(L10n.verbatim(value, reason: .userContent))
    }

    static func filesystemPath(_ value: String) -> String {
        L10n.resolve(L10n.verbatim(value, reason: .filesystemPath))
    }

    static func technicalDetail(_ value: String) -> String {
        L10n.resolve(L10n.verbatim(value, reason: .technicalDetail))
    }

    private static func file(
        id: Int64,
        path: String,
        name: String,
        category: String,
        storageMode: String,
        origin: String = "Imported"
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: filesystemPath(path),
            originalName: userContent(name),
            currentName: userContent(name),
            category: category,
            sizeBytes: 32768 + id,
            hashSha256: "developer-file-action-\(id)",
            storageMode: storageMode,
            origin: origin,
            sourcePath: nil,
            importedAt: timestamp - id,
            updatedAt: timestamp - id
        )
    }

    private static func categoryNode(
        slug: String,
        displayName: String,
        fileCount: Int64
    ) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: slug,
            displayName: userContent(displayName),
            fileCount: fileCount,
            children: []
        )
    }

    private static func tag(
        value: String,
        label: String,
        fileCount: Int64,
        selected: Bool = false
    ) -> TagRecordSnapshot {
        TagRecordSnapshot(
            value: value,
            label: label,
            fileCount: fileCount,
            selected: selected,
            disabled: false,
            updatedAt: timestamp
        )
    }
}
#endif
