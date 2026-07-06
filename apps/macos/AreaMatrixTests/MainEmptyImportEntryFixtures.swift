@testable import AreaMatrix

extension RepositoryOpeningResult {
    static func mainEmptyImportFixture(repoPath: String) -> RepositoryOpeningResult {
        RepositoryOpeningResult(
            config: .testFixture(repoPath: repoPath),
            tree: .testRoot(displayName: "资料库"),
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
