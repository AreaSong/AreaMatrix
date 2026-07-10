@testable import AreaMatrix
import Foundation

@MainActor
struct MainEmptyImportEntryFixture {
    let opening: RepositoryOpeningResult
    let model: OnboardingModel
    let accessibilityAnnouncer: RecordingAccessibilityAnnouncer
}

@MainActor
func makeMainEmptyImportEntryFixture(
    repoPath: String = "/tmp/empty-repo",
    importURLs: [URL]? = nil,
    systemCapabilityChecker: any OnboardingSystemCapabilityChecking = StaticOnboardingSystemCapabilityChecker(),
    accessibilityAnnouncer: RecordingAccessibilityAnnouncer? = nil
) -> MainEmptyImportEntryFixture {
    let opening = RepositoryOpeningResult.mainEmptyImportFixture(repoPath: repoPath)
    let accessibilityAnnouncer = accessibilityAnnouncer ?? RecordingAccessibilityAnnouncer()
    let model = makeShellOnboardingModel(
        settingsReader: StaticSettingsReader(repoPath: nil),
        systemCapabilityChecker: systemCapabilityChecker,
        accessibilityAnnouncer: accessibilityAnnouncer,
        importPicker: MainEmptyImportStaticImportPicker(urls: importURLs)
    )
    return MainEmptyImportEntryFixture(
        opening: opening,
        model: model,
        accessibilityAnnouncer: accessibilityAnnouncer
    )
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
}
