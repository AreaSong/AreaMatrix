@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func mainEmptyImportFixture(repoPath: String) -> RepositoryOpeningResult {
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
            tree: RepositoryTreeNodeSnapshot(slug: "__root__", displayName: "资料库", fileCount: 0, children: []),
            currentCategoryFiles: []
        )
    }
}

extension MainEmptyCommandPaletteKeyboardTargets {
    static let fixture: MainEmptyCommandPaletteKeyboardTargets = {
        let first = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "import",
            action: .openSheet,
            route: "import"
        )
        let disabled = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "disabled",
            action: .openSheet,
            route: "batch-add-tags",
            disabled: true
        )
        let last = CommandTargetSnapshot.commandPaletteRouteFixture(
            id: "settings",
            action: .navigate,
            route: "settings"
        )

        return MainEmptyCommandPaletteKeyboardTargets(first: first, last: last, allTargets: [first, disabled, last])
    }()
}
