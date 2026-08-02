import XCTest

final class SwiftFileSizeGovernanceTests: MacOSGovernanceTestCase {
    private let nearLimitThreshold = 450
    private let hardLimit = 500
    private let nearLimitInventory: [NearLimitSwiftFile] = [
        NearLimitSwiftFile(
            path: "AreaMatrix/Features/AI/AISettingsPane.swift",
            owner: "AI settings route and feature dependency composition",
            rationale: "Keeps the settings route state, sheet composition, and AI-specific presentation sections "
                + "under one feature owner while dependency injection is completed.",
            splitTrigger: "Before any growth beyond the current inventory, extract AISettingsPaneDependencies "
                + "and route sheet composition into dedicated support files.",
            maximumLineCount: 470
        ),
        NearLimitSwiftFile(
            path: "AreaMatrix/Features/AI/AISummaryEditorView.swift",
            owner: "AI summary editor presentation and recovery route",
            rationale: "Keeps summary editing, privacy confirmation, and call-log recovery presentation under "
                + "the AI feature owner while the summary workflow remains a single user-facing surface.",
            splitTrigger: "Before any growth beyond the current inventory, extract summary recovery sheet "
                + "composition into a dedicated AI summary route support file.",
            maximumLineCount: 461
        ),
        NearLimitSwiftFile(
            path: "AreaMatrix/App/ObservabilityRuntimeAssembly.swift",
            owner: "application observability runtime lifecycle",
            rationale: "Keeps startup, session recovery, mode lease, mutation ordering, and coordinated stop "
                + "under the same process-lifecycle owner.",
            splitTrigger: "Before any growth beyond the current inventory, extract the ordered stop state and "
                + "deadline race into a dedicated runtime stop coordinator.",
            maximumLineCount: 451
        ),
        NearLimitSwiftFile(
            path: "AreaMatrixTests/AreaMatrixDeveloperScenarioTests.swift",
            owner: "developer scenario and preview coverage contract tests",
            rationale: "Keeps the scenario inventory, language matrix, and in-memory scenario smoke assertions "
                + "together so the debug UI surface remains covered by one governance owner.",
            splitTrigger: "Before any growth beyond the current inventory, move scenario fixture smoke assertions "
                + "into a dedicated AreaMatrixDeveloperScenarioFixtureTests.swift file.",
            maximumLineCount: 460
        ),
        NearLimitSwiftFile(
            path: "AreaMatrixTests/DetailMetaPageFeatureTests.swift",
            owner: "missing-file detail and relink feature tests",
            rationale: "Keeps the Locate cancellation, hash safety, pagination, and selection-race "
                + "regressions together at the detail feature boundary.",
            splitTrigger: "Before any growth beyond the current inventory, move recovery test doubles "
                + "into DetailMetaTestSupport.swift and retain only feature assertions here.",
            maximumLineCount: 500
        ),
        NearLimitSwiftFile(
            path: "AreaMatrixTests/MainListFilesTests.swift",
            owner: "main-list pagination feature tests",
            rationale: "Keeps first-page, Load More, retry, deduplication, and search isolation "
                + "regressions together at the list feature boundary.",
            splitTrigger: "Before any growth beyond the current inventory, move pagination listers and "
                + "fixture builders into a feature-local support file.",
            maximumLineCount: 497
        ),
        NearLimitSwiftFile(
            path: "AreaMatrixTests/MacOSArchitectureBoundaryGovernanceTests.swift",
            owner: "macOS architecture and platform-boundary governance tests",
            rationale: "Keeps the cross-layer source inventories and their regression assertions together so "
                + "new boundary violations fail from one governance surface.",
            splitTrigger: "Before any growth beyond the current inventory, extract platform-boundary scans "
                + "into a dedicated governance test support file.",
            maximumLineCount: 454
        )
    ]

    func testHandwrittenSwiftFilesStayWithinHardLimit() throws {
        let violations = try handwrittenMacOSSwiftFiles().compactMap { fileURL -> String? in
            let lineCount = try swiftLineCount(in: fileURL)
            guard lineCount > hardLimit else { return nil }
            return "\(relativeMacOSPath(for: fileURL)):\(lineCount)"
        }

        XCTAssertEqual(
            violations.sorted(),
            [],
            "Handwritten Swift files must stay at or below 500 lines; generated bindings are reviewed separately."
        )
    }

    func testNearLimitHandwrittenSwiftFilesStayInventoriedWithoutGrowing() throws {
        let entries: [(String, Int)] = try handwrittenMacOSSwiftFiles().compactMap { fileURL in
            let lineCount = try swiftLineCount(in: fileURL)
            guard lineCount >= nearLimitThreshold else { return nil }
            return (relativeMacOSPath(for: fileURL), lineCount)
        }
        let actual = Dictionary(uniqueKeysWithValues: entries)
        let expectedPaths = nearLimitInventory.map(\.path).sorted()

        XCTAssertEqual(
            actual.keys.sorted(),
            expectedPaths,
            "Every handwritten Swift file at or above 450 lines needs an owner, rationale, and split trigger."
        )

        let growthViolations = nearLimitInventory.compactMap { item -> String? in
            guard let lineCount = actual[item.path], lineCount > item.maximumLineCount else { return nil }
            return "\(item.path):\(lineCount)>\(item.maximumLineCount)"
        }
        XCTAssertEqual(
            growthViolations,
            [],
            "Near-limit Swift files cannot grow; split the documented owner boundary first."
        )
    }

    func testNearLimitInventoryDocumentsOwnershipAndExitConditions() {
        let incomplete = nearLimitInventory.compactMap { item -> String? in
            guard item.owner.isEmpty || item.rationale.isEmpty || item.splitTrigger.isEmpty else { return nil }
            return item.path
        }

        XCTAssertEqual(incomplete, [], "Near-limit inventory entries must document ownership and an exit condition.")
    }
}

private struct NearLimitSwiftFile {
    let path: String
    let owner: String
    let rationale: String
    let splitTrigger: String
    let maximumLineCount: Int
}
