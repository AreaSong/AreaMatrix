@testable import AreaMatrix
import Foundation

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
}
