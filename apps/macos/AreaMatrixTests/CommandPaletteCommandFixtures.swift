@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func commandPaletteCommandFixture(repoPath: String, files: [FileEntrySnapshot]) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .mainLoadingFixture(repoPath: repoPath),
            tree: .commandPaletteCommandFixtureTree(),
            currentCategoryFiles: files
        )
    }
}

extension RepositoryTreeNodeSnapshot {
    static func commandPaletteCommandFixtureTree() -> RepositoryTreeNodeSnapshot {
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

extension CoreErrorMappingSnapshot {
    static func commandPaletteCommandDb(rawContext: String) -> CoreErrorMappingSnapshot {
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
    static func commandPaletteCommandFileFixture(id: Int64, currentName: String) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: "docs/\(currentName)",
            originalName: currentName,
            currentName: currentName,
            category: "docs",
            sizeBytes: 256,
            hashSha256: "commandPalette-command-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000,
            updatedAt: 1_700_000_100
        )
    }
}

extension SavedSearchSnapshot {
    static func commandPaletteCommandPaletteFixture() -> SavedSearchSnapshot {
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
    static func commandPaletteCommandSmartListPage(saved: SavedSearchSnapshot) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: saved.query.query,
            totalCount: 0,
            results: [],
            diagnostics: [],
            indexStatus: .ready
        )
    }

    static func commandPaletteCommandSmartListPage(
        saved: SavedSearchSnapshot,
        files: [FileEntrySnapshot]
    ) -> SearchResultPageSnapshot {
        SearchResultPageSnapshot(
            query: saved.query.query,
            totalCount: Int64(files.count),
            results: files.map {
                SearchFileResultSnapshot(
                    file: $0,
                    score: 1,
                    matches: [
                        SearchMatchSnapshot(
                            fieldDisplayName: "Name",
                            kindDisplayName: "Smart List match",
                            snippet: $0.currentName
                        )
                    ],
                    noteSnippet: nil
                )
            },
            diagnostics: [],
            indexStatus: .ready
        )
    }
}

extension CommandTargetSnapshot {
    static func commandPaletteRouteFixture(
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
    static func commandPaletteFixture(
        commands: [CommandTarget] = [],
        smartLists: [CommandTarget] = []
    ) -> CommandIndex {
        CommandIndex(
            commands: commands,
            navigationTargets: [],
            currentSelectionTargets: [],
            recentTargets: [],
            smartLists: smartLists,
            fileCandidates: [],
            generatedAt: 1_700_000_000
        )
    }
}

extension CommandTarget {
    static func commandPaletteFixture(
        id: String,
        title: String,
        action: CommandTargetAction,
        route: String?,
        savedSearchID: Int64? = nil
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
            savedSearchId: savedSearchID
        )
    }
}
