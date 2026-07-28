import XCTest

final class MacOSFeatureOwnershipGovernanceTests: MacOSGovernanceTestCase {
    private let featureOwnerInventory = [
        FeatureOwnerInventory(
            name: "AI",
            responsibility: "Privacy rules, provider configuration, summaries, classification, tags, and " +
                "local/remote AI status.",
            riskBoundary: "User-data privacy, credentials, Keychain, network access, and probe process execution.",
            validationFocus: "AI privacy, provider configuration, credential lifecycle, and summary/tag integration " +
                "tests."
        ),
        FeatureOwnerInventory(
            name: "CommandPalette",
            responsibility: "Command discovery, focus restoration, and contextual command routing.",
            riskBoundary: "Presentation and routing only; commands delegate execution to their owning feature.",
            validationFocus: "Command palette feature and route-host governance tests."
        ),
        FeatureOwnerInventory(
            name: "Detail",
            responsibility: "Selected-file detail, notes, tags, metadata, logs, and multi-selection summaries.",
            riskBoundary: "Read/write actions remain behind FileActions or CoreBridge contracts.",
            validationFocus: "Detail page, tag, note, metadata, log, and multi-selection tests."
        ),
        FeatureOwnerInventory(
            name: "Diagnostics",
            responsibility: "Runtime evidence, incident capture, user activity, developer console, and diagnostic " +
                "package preview and inspection.",
            riskBoundary: "Privacy-safe local evidence and explicit no-overwrite package export; business writes " +
                "stay with their owning feature.",
            validationFocus: "Observability ingress, storage, privacy, incident, hostile package, and projection tests."
        ),
        FeatureOwnerInventory(
            name: "FileActions",
            responsibility: "Rename, delete, category move, batch actions, tags, confirmations, refresh, and " +
                "undo routing.",
            riskBoundary: "User-file mutation, confirmation, Core consistency, and undo policy.",
            validationFocus: "File action feature/integration tests and file-safety acceptance evidence."
        ),
        FeatureOwnerInventory(
            name: "Import",
            responsibility: "Single-file, folder, batch, progress, result, conflict, duplicate, and placeholder flows.",
            riskBoundary: "Source files, final repository state, DB consistency, iCloud placeholders, and session " +
                "recovery.",
            validationFocus: "Import feature/integration tests plus file-safety and recovery evidence."
        ),
        FeatureOwnerInventory(
            name: "MainList",
            responsibility: "Visible files, filtering, selection, loading, empty/error presentation, and feature " +
                "entry contracts.",
            riskBoundary: "Cross-feature composition only; execution remains with Detail, FileActions, Search, or " +
                "Import.",
            validationFocus: "MainList, route-host, visible-file, and content-shell governance tests."
        ),
        FeatureOwnerInventory(
            name: "Onboarding",
            responsibility: "Welcome, path validation, initialization, startup recovery, DB repair, and main loading.",
            riskBoundary: "Repository opening, initialization writes, recovery, DB repair, and user-file safety.",
            validationFocus: "Onboarding feature/integration tests and initialization/recovery evidence."
        ),
        FeatureOwnerInventory(
            name: "RepositoryLifecycle",
            responsibility: "Repository-level errors, lifecycle presentation, and shared open/recovery entry " +
                "contracts.",
            riskBoundary: "Repository availability and Core error mapping; no direct user-file mutation.",
            validationFocus: "Repository lifecycle and error recovery tests."
        ),
        FeatureOwnerInventory(
            name: "Search",
            responsibility: "Normal, semantic, saved, smart-list, filter, diagnostic, and search presentation routing.",
            riskBoundary: "Query diagnostics and privacy-aware semantic search; Core calls remain in Bridge.",
            validationFocus: "Search page/integration, diagnostic, semantic, and route-host tests."
        ),
        FeatureOwnerInventory(
            name: "Settings",
            responsibility: "General, repository, classifier, integrations, advanced, about, and platform " +
                "differences settings.",
            riskBoundary: "Configuration writes, dangerous settings, diagnostics export, iCloud state, and platform " +
                "actions.",
            validationFocus: "Settings feature/integration tests and configuration/file-safety evidence."
        ),
        FeatureOwnerInventory(
            name: "SyncConflicts",
            responsibility: "iCloud and external sync conflict listing, review, preview, resolve, and replace " +
                "confirmation.",
            riskBoundary: "External changes, iCloud copies, conflict resolution, and user-file selection.",
            validationFocus: "Sync conflict, iCloud conflict, replace confirmation, and file-action integration tests."
        )
    ]

    func testFeatureDirectoriesStayOwnedAndInventoried() throws {
        let actual = try productionFeatureDirectories()
        let expected = featureOwnerInventory.map(\.name).sorted()

        XCTAssertEqual(
            actual,
            expected,
            "Every Features directory must have an explicit owner inventory entry before new feature code lands."
        )
    }

    func testFeatureOwnerInventoryDocumentsResponsibilityRiskAndValidation() {
        let incomplete = featureOwnerInventory.compactMap { item -> String? in
            guard !item.responsibility.isEmpty,
                  !item.riskBoundary.isEmpty,
                  !item.validationFocus.isEmpty
            else {
                return item.name
            }
            return nil
        }

        XCTAssertEqual(
            incomplete,
            [],
            "Each feature owner entry must document responsibility, risk boundary, and validation focus."
        )
    }
}

private struct FeatureOwnerInventory {
    let name: String
    let responsibility: String
    let riskBoundary: String
    let validationFocus: String
}
