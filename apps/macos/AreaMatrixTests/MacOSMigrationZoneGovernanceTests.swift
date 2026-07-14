import XCTest

final class MacOSMigrationZoneGovernanceTests: MacOSGovernanceTestCase {
    private let migrationZoneInventory = [
        MigrationZoneSwiftFile(
            path: "Views/MainWindow.swift",
            owner: "App window shell",
            exitCondition: "Keep only cross-feature window composition; feature UI belongs in Features."
        ),
        MigrationZoneSwiftFile(
            path: "Views/MainWindowRouteContent.swift",
            owner: "App route shell",
            exitCondition: "Keep only top-level route composition; feature routes belong with their owner."
        ),
        MigrationZoneSwiftFile(
            path: "Views/Main/MainRepositoryContentLifecycle.swift",
            owner: "Main content shell lifecycle",
            exitCondition: "Remove feature-specific modifiers as their owners become stable."
        ),
        MigrationZoneSwiftFile(
            path: "Views/Main/MainRepositoryContentSidebar.swift",
            owner: "Main sidebar composition",
            exitCondition: "Keep only cross-feature sidebar composition and shared entry wiring."
        ),
        MigrationZoneSwiftFile(
            path: "Views/Main/MainRepositoryContentToolbar.swift",
            owner: "Main toolbar composition",
            exitCondition: "Keep only cross-feature toolbar composition and feature entry wiring."
        ),
        MigrationZoneSwiftFile(
            path: "Views/Main/MainRepositoryContentView.swift",
            owner: "Main content shell",
            exitCondition: "Keep only feature-owned contract composition and View-owned state identity."
        ),
        MigrationZoneSwiftFile(
            path: "Views/Settings/SettingsFormSection.swift",
            owner: "Settings shared scaffold",
            exitCondition: "Keep only presentation-only controls reused by multiple settings panes."
        ),
        MigrationZoneSwiftFile(
            path: "Views/Settings/SettingsKeyValueRow.swift",
            owner: "Settings shared scaffold",
            exitCondition: "Keep only presentation-only controls reused by multiple settings panes."
        ),
        MigrationZoneSwiftFile(
            path: "Views/Settings/SettingsPageScaffold.swift",
            owner: "Settings shared scaffold",
            exitCondition: "Keep only presentation-only layout reused by multiple settings panes."
        )
    ]

    func testLegacyMigrationZonesDoNotExpand() throws {
        let actual = try productionSwiftFiles()
            .map { relativeProductionPath(for: $0) }
            .filter(isControlledMigrationZoneFile)
            .sorted()
        let expected = migrationZoneInventory.map(\.path).sorted()

        XCTAssertEqual(
            actual,
            expected,
            "Legacy Models and Views migration zones must not gain new business files; use the owning Feature instead."
        )
    }

    func testMigrationZoneInventoryDocumentsOwnerAndExitCondition() {
        let incomplete = migrationZoneInventory.compactMap { item -> String? in
            item.owner.isEmpty || item.exitCondition.isEmpty ? item.path : nil
        }

        XCTAssertEqual(incomplete, [], "Every retained migration-zone file needs an owner and exit condition.")
    }

    private func isControlledMigrationZoneFile(_ path: String) -> Bool {
        path.hasPrefix("Models/") ||
            path.hasPrefix("Views/Main/") ||
            path.hasPrefix("Views/Onboarding/") ||
            path.hasPrefix("Views/Settings/") ||
            isRootViewsFile(path)
    }

    private func isRootViewsFile(_ path: String) -> Bool {
        path.hasPrefix("Views/") && path.split(separator: "/").count == 2
    }
}

private struct MigrationZoneSwiftFile {
    let path: String
    let owner: String
    let exitCondition: String
}
