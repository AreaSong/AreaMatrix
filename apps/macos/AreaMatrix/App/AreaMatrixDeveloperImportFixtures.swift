import Foundation

#if DEBUG
enum DeveloperImportScenarioFixture {
    static let repoPath = AreaMatrixPreviewFixtures.repositoryPath
    static let sourceRoot = URL(fileURLWithPath: "/developer-fixtures/incoming", isDirectory: true)

    static var singleFileRequest: ImportEntryRequest {
        ImportEntryRequest(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
            repoPath: repoPath,
            source: .filePicker,
            destination: .autoClassify,
            urls: [sourceRoot.appendingPathComponent("quarterly-report.pdf")],
            kind: .singleFile,
            availableCategories: ["docs", "finance", "inbox"]
        )
    }

    static var folderRequest: ImportEntryRequest {
        ImportEntryRequest(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2)),
            repoPath: repoPath,
            source: .dropZone,
            destination: .autoClassify,
            urls: [sourceRoot],
            kind: .folder,
            availableCategories: ["docs", "finance", "inbox"]
        )
    }

    static var opening: RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: AppRepoConfigSnapshot(
                repoPath: repoPath,
                revision: 12,
                defaultMode: "Copied",
                overviewOutput: "GeneratedOnly",
                aiEnabled: false,
                locale: "system",
                iCloudWarn: true,
                enableExtensionRules: true,
                enableKeywordRules: true,
                fallbackToInbox: true,
                allowReplaceDuringImport: false
            ),
            tree: repositoryTree,
            currentCategoryFiles: [DeveloperFileActionScenarioFixture.primaryFile]
        )
    }

    static var progressState: ImportProgressRouteState {
        ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: sourcePath("invoice-2026.pdf"),
            status: .running,
            completed: 1,
            failed: 0,
            remaining: 2,
            items: progressItems,
            isRepositoryFinderAvailable: false
        )
    }

    static var resultState: ImportResultRouteState {
        ImportResultRouteState(
            sourceOpening: opening,
            imported: 2,
            failed: 1,
            stopped: 1,
            pending: 0,
            currentPath: sourcePath("restricted-notes.md"),
            items: resultItems,
            changeLog: .loaded(changeLogEntries)
        )
    }

    static var folderRows: [ImportFolderPreviewRow] {
        [
            folderRow("quarterly-report.pdf", sizeBytes: 48128),
            folderRow("invoice-2026.pdf", sizeBytes: 36400),
            folderRow("meeting-notes.md", sizeBytes: 8192),
            folderRow("product-brief.pages", sizeBytes: 72704)
        ]
    }

    static func prediction(filename: String) -> ClassifyResultSnapshot {
        let isFinance = filename.localizedCaseInsensitiveContains("invoice")
        return ClassifyResultSnapshot(
            category: isFinance ? "finance" : "docs",
            suggestedName: filename,
            reason: isFinance ? .keyword : .extension,
            confidence: isFinance ? 0.96 : 0.91
        )
    }

    static func importedFile(filename: String, category: String, storageMode: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: 2000 + Int64(filename.count),
            path: filesystemPath("\(category)/\(filename)"),
            originalName: userContent(filename),
            currentName: userContent(filename),
            category: category,
            sizeBytes: 48128,
            hashSha256: "developer-import-\(filename.count)",
            storageMode: storageMode,
            origin: "Imported",
            sourcePath: sourcePath(filename),
            importedAt: 1_778_738_400,
            updatedAt: 1_778_738_400
        )
    }

    private static var repositoryTree: RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: userContent("AreaMatrix Developer Repository"),
            kind: "Root",
            fileCount: 0,
            depth: 0,
            children: [
                categoryNode("docs", name: "Documents", fileCount: 2),
                categoryNode("finance", name: "Finance", fileCount: 1),
                categoryNode("inbox", name: "Inbox", fileCount: 0)
            ]
        )
    }

    private static var progressItems: [ImportBatchProgressSnapshot.Item] {
        [
            .init(
                fileID: 2001,
                sourcePath: sourcePath("quarterly-report.pdf"),
                targetPath: "docs/quarterly-report.pdf",
                phase: .done
            ),
            .init(
                sourcePath: sourcePath("invoice-2026.pdf"),
                targetPath: "finance/invoice-2026.pdf",
                phase: .copying
            ),
            .init(
                sourcePath: sourcePath("meeting-notes.md"),
                targetPath: "docs/meeting-notes.md",
                phase: .pending
            )
        ]
    }

    private static var resultItems: [ImportResultRouteState.Item] {
        [
            resultItem(2001, "quarterly-report.pdf", "docs/quarterly-report.pdf", .imported, "-"),
            resultItem(2002, "invoice-2026.pdf", "finance/invoice-2026.pdf", .sourceRetained,
                       L10n.string("import.result.source-retained.reason")),
            resultItem(nil, "duplicate-report.pdf", "docs/duplicate-report.pdf", .skipped,
                       L10n.string("Duplicate file"), existingRelativePath: "docs/quarterly-report.pdf"),
            resultItem(nil, "restricted-notes.md", "docs/restricted-notes.md", .failed,
                       L10n.string("Permission denied"))
        ]
    }

    private static var changeLogEntries: [ChangeLogEntrySnapshot] {
        [
            ChangeLogEntrySnapshot(
                id: 9001,
                fileID: 2001,
                filename: userContent("quarterly-report.pdf"),
                category: "docs",
                action: "imported",
                detailJSON: "{\"mode\":\"Copied\"}",
                occurredAt: 1_778_738_400
            )
        ]
    }

    private static func folderRow(_ filename: String, sizeBytes: Int64) -> ImportFolderPreviewRow {
        ImportFolderPreviewRow(
            fileURL: sourceRoot.appendingPathComponent(filename),
            rootURL: sourceRoot,
            originalName: userContent(filename),
            relativePath: filename,
            sizeBytes: sizeBytes,
            predictedCategory: nil,
            suggestedName: filename,
            status: .loading
        )
    }

    private static func resultItem(
        _ fileID: Int64?,
        _ sourceName: String,
        _ targetPath: String,
        _ status: ImportResultRouteState.ItemStatus,
        _ reason: String,
        existingRelativePath: String? = nil
    ) -> ImportResultRouteState.Item {
        ImportResultRouteState.Item(
            fileID: fileID,
            sourcePath: sourcePath(sourceName),
            targetPath: targetPath,
            status: status,
            reason: reason,
            retryContext: nil,
            existingRelativePath: existingRelativePath
        )
    }

    private static func categoryNode(
        _ slug: String,
        name: String,
        fileCount: Int64
    ) -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: slug,
            displayName: userContent(name),
            fileCount: fileCount,
            children: []
        )
    }

    private static func sourcePath(_ filename: String) -> String {
        filesystemPath(sourceRoot.appendingPathComponent(filename).path)
    }

    private static func userContent(_ value: String) -> String {
        L10n.resolve(L10n.verbatim(value, reason: .userContent))
    }

    private static func filesystemPath(_ value: String) -> String {
        L10n.resolve(L10n.verbatim(value, reason: .filesystemPath))
    }
}
#endif
