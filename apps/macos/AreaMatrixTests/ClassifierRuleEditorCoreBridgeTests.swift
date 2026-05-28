@testable import AreaMatrix
import XCTest

final class ClassifierRuleEditorCoreBridgeTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testS219DefaultCoreBridgePersistsClassifierRuleCrudToClassifierYaml() async throws {
        let repoURL = try temporaryS219Repo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let initial = try await bridge.listClassifierRules(repoPath: repoURL.path)
        XCTAssertTrue(initial.rules.contains { $0.ruleID == "finance" })

        let created = try await bridge.createClassifierRule(
            repoPath: repoURL.path,
            request: ClassifierRuleCreateRequestSnapshot(
                slug: "tax",
                displayName: "Tax",
                description: "Tax documents",
                extensions: ["pdf"],
                keywords: ["tax"],
                priority: 20,
                namingTemplate: "{stem}"
            )
        )
        XCTAssertEqual(created.updatedRuleID, "tax")
        XCTAssertTrue(try classifierYaml(repoURL).contains("slug: tax"))

        let updated = try await bridge.updateClassifierRule(
            repoPath: repoURL.path,
            request: ClassifierRuleUpdateSnapshot(
                ruleID: "tax",
                slug: "tax",
                displayName: "Tax Records",
                description: "Tax documents",
                extensions: ["pdf", "csv"],
                keywords: ["tax", "irs"],
                priority: 30,
                namingTemplate: "{stem}-{date}",
                previewConfirmed: true
            )
        )
        XCTAssertEqual(updated.updatedRuleID, "tax")
        let updatedYaml = try classifierYaml(repoURL)
        XCTAssertTrue(updatedYaml.contains("display_name"))
        XCTAssertTrue(updatedYaml.contains("Tax Records"))
        XCTAssertTrue(updatedYaml.contains("csv"))

        let deleted = try await bridge.deleteClassifierRule(
            repoPath: repoURL.path,
            request: ClassifierRuleDeleteRequestSnapshot(
                ruleID: "tax",
                replacementCategory: "inbox",
                previewConfirmed: true
            )
        )
        XCTAssertEqual(deleted.updatedRuleID, "inbox")
        XCTAssertFalse(try classifierYaml(repoURL).contains("slug: tax"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }
}

private func temporaryS219Repo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixS219-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func classifierYaml(_ repoURL: URL) throws -> String {
    let url = repoURL
        .appendingPathComponent(".areamatrix", isDirectory: true)
        .appendingPathComponent("classifier.yaml", isDirectory: false)
    return try String(contentsOf: url, encoding: .utf8)
}
