@testable import AreaMatrix
import XCTest

final class ClassifierSettingsRecoveryTests: XCTestCase {
    @MainActor
    func testCreateDefaultClassifierYamlCreatesOnlyMetadataFileAndStoresBackup() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        try FileManager.default.createDirectory(
            at: repoURL.appendingPathComponent(".areamatrix", isDirectory: true),
            withIntermediateDirectories: true
        )
        let predictor = ClassifierSettingsSequencePredictor(results: [.success(classifierRecoveryProbeResult())])
        let model = await classifierSettingsRecoveryModel(repoURL: repoURL, predictor: predictor)

        await model.createDefaultClassifierYaml()

        let classifierURL = classifierURL(repoURL: repoURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: classifierURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lastValidBackupURL(repoURL: repoURL).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
        XCTAssertEqual(model.validationState, .passed)
        XCTAssertTrue(model.canRevertToLastValid)
        let requests = await predictor.requests()
        XCTAssertEqual(requests, [
            ClassifierSettingsSequencePredictor.Request(
                repoPath: repoURL.path,
                filename: "AreaMatrixValidationProbe.txt"
            )
        ])
    }

    @MainActor
    func testCreateDefaultClassifierYamlDoesNotOverwriteExistingRules() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let existing = "version: 1\ndefault: inbox\ncategories: []\n"
        try writeClassifier(existing, repoURL: repoURL)
        let predictor = ClassifierSettingsSequencePredictor(results: [.success(classifierRecoveryProbeResult())])
        let model = await classifierSettingsRecoveryModel(repoURL: repoURL, predictor: predictor)

        await model.createDefaultClassifierYaml()

        XCTAssertEqual(try String(contentsOf: classifierURL(repoURL: repoURL), encoding: .utf8), existing)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lastValidBackupURL(repoURL: repoURL).path))
        XCTAssertEqual(model.fileActionError?.message, "无法创建默认分类规则文件")
        let requests = await predictor.requests()
        XCTAssertEqual(requests, [])
    }

    @MainActor
    func testValidateStoresLastValidBackupAndRevertRestoresThatContent() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let original = """
        version: 1
        default: inbox
        categories:
          - slug: inbox
            display_name: { en: Inbox }
        """
        try writeClassifier(original, repoURL: repoURL)
        let predictor = ClassifierSettingsSequencePredictor(results: [
            .success(classifierRecoveryProbeResult()),
            .success(classifierRecoveryProbeResult())
        ])
        let model = await classifierSettingsRecoveryModel(repoURL: repoURL, predictor: predictor)

        let validated = await model.validateClassifierRules()
        try writeClassifier("version: 1\ndefault: broken\ncategories: []\n", repoURL: repoURL)
        await model.revertToLastValid()

        XCTAssertTrue(validated)
        XCTAssertEqual(try String(contentsOf: classifierURL(repoURL: repoURL), encoding: .utf8), original)
        XCTAssertEqual(try String(contentsOf: lastValidBackupURL(repoURL: repoURL), encoding: .utf8), original)
        XCTAssertEqual(model.validationState, .passed)
        XCTAssertTrue(model.canRevertToLastValid)
        let requests = await predictor.requests()
        XCTAssertEqual(requests.count, 2)
    }

    @MainActor
    func testValidationFailureShowsLineFieldAndErrorText() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        try writeClassifier("version: 1\ndefault: inbox\ncategories: []\n", repoURL: repoURL)
        let predictor = ClassifierSettingsSequencePredictor(results: [
            .failure(CoreError.Config(reason: "categories[2].slug duplicate at line 47 column 5"))
        ])
        let model = await classifierSettingsRecoveryModel(repoURL: repoURL, predictor: predictor)

        let validated = await model.validateClassifierRules()

        XCTAssertFalse(validated)
        XCTAssertEqual(model.validationStatusLabel, "Failed")
        XCTAssertEqual(
            model.validationError?.message,
            "分类规则无效：categories[2].slug duplicate at line 47 column 5 (field categories[2].slug, line 47)"
        )
        XCTAssertEqual(model.validationError?.recovery, "Open classifier.yaml and fix the reported line and field.")
    }
}
