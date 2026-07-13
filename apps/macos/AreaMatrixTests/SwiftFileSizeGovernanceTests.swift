import XCTest

final class SwiftFileSizeGovernanceTests: MacOSGovernanceTestCase {
    private let nearLimitThreshold = 450
    private let hardLimit = 500
    private let nearLimitInventory = [
        NearLimitSwiftFile(
            path: "AreaMatrix/App/AppPlatformServiceAdapters.swift",
            owner: "App platform service adapters",
            rationale: "Keeps app-wide AppKit and local file adapters visible behind one composition boundary.",
            splitTrigger: "Split by interaction, file URL, picker, and export adapter families before adding lines.",
            maximumLineCount: 462
        ),
        NearLimitSwiftFile(
            path: "AreaMatrixTests/ConfigurationFixtures.swift",
            owner: "Cross-feature snapshot fixtures",
            rationale: "Centralizes canonical Core snapshot builders shared by configuration and repository tests.",
            splitTrigger: "Move a complete snapshot fixture family to feature-local support before adding lines.",
            maximumLineCount: 479
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
