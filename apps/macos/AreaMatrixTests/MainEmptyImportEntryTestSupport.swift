@testable import AreaMatrix
import Foundation

actor CommandPaletteNoopUndoStore: CoreUndoActionLogging {
    func listUndoActions(repoPath _: String) async throws -> [UndoActionRecordSnapshot] {
        []
    }

    func undoAction(repoPath _: String, actionID _: String) async throws -> UndoActionResultSnapshot {
        throw CoreError.Internal(message: "command-palette/redo-action-log test does not execute undo actions")
    }
}

struct MainEmptyImportStaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

struct MainEmptyImportNoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

struct MainEmptyImportStaticImportPicker: RepositoryImportPicking {
    let urls: [URL]?

    @MainActor
    func chooseImportURLs() -> [URL]? {
        urls
    }
}

@MainActor
final class MainEmptyImportAnnouncer: AccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    func announce(_ message: String) {
        announcements.append(message)
    }
}

struct MainEmptyCommandPaletteRouteCase {
    let route: String
    let action: CommandTargetActionSnapshot
    let expectedRoute: CommandPaletteTargetRoute

    var targetID: String {
        "target-\(route)-\(action.rawValue)"
    }

    var requiresConfirmation: Bool {
        route == "import-conflict-batch"
    }

    static let pageSpecRoutes: [MainEmptyCommandPaletteRouteCase] = [
        .init(
            route: "classifier-impact-preview",
            action: .navigate,
            expectedRoute: .linkedPage(.classifierImpactPreview)
        ),
        .init(
            route: "classifier-impact-preview",
            action: .openSheet,
            expectedRoute: .linkedPage(.classifierImpactPreview)
        ),
        .init(
            route: "import-conflict-batch",
            action: .openSheet,
            expectedRoute: .linkedPage(.importConflictBatch)
        ),
        .init(route: "redo-action-log", action: .navigate, expectedRoute: .linkedPage(.redo)),
        .init(route: "tag-suggestions", action: .navigate, expectedRoute: .linkedPage(.tagSuggestions)),
        .init(route: "classifier-rule-editor", action: .navigate, expectedRoute: .classifierRuleEditor)
    ]
}

struct MainEmptyCommandPaletteKeyboardTargets {
    let first: CommandTargetSnapshot
    let last: CommandTargetSnapshot
    let allTargets: [CommandTargetSnapshot]

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
