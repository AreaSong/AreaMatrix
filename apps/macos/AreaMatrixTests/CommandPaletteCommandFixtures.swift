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
        RepositoryTreeNodeSnapshot.testRoot(children: [
            .testCategory("docs", fileCount: 1)
        ])
    }
}

extension CoreErrorMappingSnapshot {
    static func commandPaletteCommandDb(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
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
        FileEntrySnapshot.testFixture(
            id: id,
            path: "docs/\(currentName)",
            currentName: currentName,
            category: "docs"
        ) {
            $0.sizeBytes = 256
            $0.hashSha256 = "commandPalette-command-\(id)"
        }
    }
}

extension SavedSearchSnapshot {
    static func commandPaletteCommandPaletteFixture() -> SavedSearchSnapshot {
        let request = SearchQueryRequestSnapshot.testFixture(query: "Finance")
        return .testFixture(
            id: 77,
            name: "Finance",
            query: .testFixture(request: request),
            pinned: true,
            updatedAt: 1_700_000_100
        )
    }
}

extension SearchResultPageSnapshot {
    static func commandPaletteCommandSmartListPage(saved: SavedSearchSnapshot) -> SearchResultPageSnapshot {
        .testFixture(query: saved.query.query)
    }

    static func commandPaletteCommandSmartListPage(
        saved: SavedSearchSnapshot,
        files: [FileEntrySnapshot]
    ) -> SearchResultPageSnapshot {
        .testFixture(
            query: saved.query.query,
            results: files.map {
                .nameMatchFixture(file: $0, kindDisplayName: "Smart List match")
            }
        )
    }
}

extension CommandPaletteSnapshot {
    static func testFixture(
        sections: [CommandPaletteSectionSnapshot] = [],
        generatedAt: Int64 = 1
    ) -> CommandPaletteSnapshot {
        CommandPaletteSnapshot(
            sections: sections,
            generatedAt: generatedAt
        )
    }

    static func testFixture(coreIndex: CoreCommandIndexSnapshot) -> CommandPaletteSnapshot {
        CommandPaletteSnapshot(coreIndex: coreIndex)
    }
}

extension CommandTargetSnapshot {
    static func testFixture(coreTarget: CoreCommandTargetSnapshot) -> CommandTargetSnapshot {
        CommandTargetSnapshot(coreTarget: coreTarget)
    }

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

extension CoreCommandIndexSnapshot {
    static func commandPaletteFixture(
        commands: [CoreCommandTargetSnapshot] = [],
        smartLists: [CoreCommandTargetSnapshot] = []
    ) -> CoreCommandIndexSnapshot {
        CoreCommandIndexSnapshot(
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

extension CoreCommandTargetSnapshot {
    static func commandPaletteFixture(
        id: String,
        title: String,
        action: CommandTargetActionSnapshot,
        route: String?,
        savedSearchID: Int64? = nil
    ) -> CoreCommandTargetSnapshot {
        CoreCommandTargetSnapshot(
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
            fileID: nil,
            savedSearchID: savedSearchID
        )
    }
}
