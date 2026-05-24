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

    static func s215CommandFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .mainLoadingFixture(repoPath: repoPath),
            tree: .s215CommandFixtureTree(),
            currentCategoryFiles: files
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

    static func s215CommandFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(slug: "docs", displayName: "docs", fileCount: 1, children: [])
            ]
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

    static func s215CommandDb(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Some commands are unavailable",
            severity: .medium,
            suggestedAction: "Retry the command palette.",
            recoverability: .retryable,
            rawContext: rawContext
        )
    }
}

extension FileEntrySnapshot {
    static func s215CommandFileFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 256,
            hashSha256: "s215-command-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension SavedSearchSnapshot {
    static func s215CommandPaletteFixture() -> SavedSearchSnapshot {
        let request = SearchQueryRequestSnapshot(
            query: "Finance",
            scope: .all,
            currentPath: nil,
            category: nil,
            filters: .empty,
            sort: .relevance,
            limit: 50,
            offset: 0
        )
        return SavedSearchSnapshot(
            id: 77,
            name: "Finance",
            query: SavedSearchQuerySnapshot(request: request),
            icon: "magnifyingglass",
            color: nil,
            pinned: true,
            createdAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension SearchResultPageSnapshot {
    static func s215CommandSmartListPage(saved: SavedSearchSnapshot) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: saved.query.query,
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

extension CommandTargetSnapshot {
    static func s215RouteFixture(
        id: String,
        title: String = "Delete selected files...",
        action: CommandTargetActionSnapshot,
        route: String?,
        disabled: Bool = false,
        disabledReason: String? = nil,
        requiresConfirmation: Bool = false,
        fileID: Int64? = nil,
        savedSearchID: Int64? = nil
    ) -> CommandTargetSnapshot {
        CommandTargetSnapshot(
            id: id,
            title: title,
            subtitle: "Open command target",
            group: .currentSelection,
            kind: .command,
            action: action,
            route: route,
            shortcut: nil,
            disabled: disabled,
            disabledReason: disabledReason,
            requiresConfirmation: requiresConfirmation,
            fileID: fileID,
            savedSearchID: savedSearchID
        )
    }
}

extension CommandIndex {
    static func s215Fixture(commands: [CommandTarget] = []) -> CommandIndex {
        CommandIndex(
            commands: commands,
            navigationTargets: [],
            currentSelectionTargets: [],
            recentTargets: [],
            smartLists: [],
            fileCandidates: [],
            generatedAt: 1_700_000_000
        )
    }
}

extension CommandTarget {
    static func s215Fixture(
        id: String,
        title: String,
        action: CommandTargetAction,
        route: String?
    ) -> CommandTarget {
        CommandTarget(
            id: id,
            title: title,
            subtitle: "Open command target",
            group: .commands,
            kind: .command,
            action: action,
            route: route,
            shortcut: "Cmd+K",
            disabled: false,
            disabledReason: nil,
            requiresConfirmation: false,
            fileId: nil,
            savedSearchId: nil
        )
    }
}

func s215CommandMirrorDescription(of value: Any) -> String {
    var lines: [String] = []
    appendS215CommandMirrorDescription(of: value, to: &lines)
    return lines.joined(separator: "\n")
}

private func appendS215CommandMirrorDescription(of value: Any, to lines: inout [String]) {
    lines.append(String(describing: type(of: value)))
    lines.append(String(describing: value))
    for child in Mirror(reflecting: value).children {
        appendS215CommandMirrorDescription(of: child.value, to: &lines)
    }
}

func makeMainLoadingTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixMainLoadingTreeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
