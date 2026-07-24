@testable import AreaMatrix
import XCTest

final class ClassifierSettingsRecoveryTests: XCTestCase {
    @MainActor
    func testMissingClassifierRequiresConfirmationBeforeCreateDefault() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierDegradedFixture(
                health: .missing,
                recoveryActions: [.createDefault]
            )),
            mutationResult: .success(.classifierEditorFixture())
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        await model.createDefaultClassifierYaml()

        XCTAssertEqual(model.classifierRuleEditor.pendingRecoveryAction, .createDefault)
        XCTAssertEqual(model.classifierRuleEditor.health, .missing)
        await editor.assertCreateDefaultRequests([])

        await model.confirmClassifierRecovery()

        await editor.assertCreateDefaultRequests([.init(
            repoPath: repoURL.path,
            confirmed: true,
            editingLocale: .en
        )])
        XCTAssertEqual(model.classifierRuleEditor.health, .valid)
        XCTAssertEqual(model.classifierRuleEditor.recoveryState, .succeeded(.createDefault))
    }

    @MainActor
    func testInvalidClassifierExposesOnlyCoreAllowedRestoreActions() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierDegradedFixture(
                health: .invalid,
                recoveryActions: [.restoreDefault, .restoreLastValid]
            )),
            mutationResult: .success(.classifierEditorFixture())
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.requestClassifierRecovery(.restoreDefault)
        await model.confirmClassifierRecovery()

        await editor.assertRestoreDefaultRequests([.init(
            repoPath: repoURL.path,
            confirmed: true,
            editingLocale: .en
        )])
        await editor.assertRestoreLastValidRequests([])
        XCTAssertEqual(model.classifierRuleEditor.recoveryState, .succeeded(.restoreDefault))
    }

    @MainActor
    func testUnreadableClassifierHasNoWriteRecoveryAction() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(listResult: .success(.classifierDegradedFixture(
            health: .unreadable,
            recoveryActions: []
        )))
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.requestClassifierRecovery(.restoreDefault)
        await model.confirmClassifierRecovery()

        XCTAssertNil(model.classifierRuleEditor.pendingRecoveryAction)
        XCTAssertEqual(model.classifierRuleEditor.health, .unreadable)
        await editor.assertRestoreDefaultRequests([])
    }

    @MainActor
    func testRecoveryFailureKeepsDegradedSnapshotAndFailureState() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierDegradedFixture(
                health: .invalid,
                recoveryActions: [.restoreDefault]
            )),
            mutationResult: .failure(CoreError.PermissionDenied(path: "classifier.yaml"))
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.requestClassifierRecovery(.restoreDefault)
        await model.confirmClassifierRecovery()

        XCTAssertEqual(model.classifierRuleEditor.health, .invalid)
        XCTAssertTrue(model.classifierRuleEditor.rules.isEmpty)
        guard case let .failed(action, mapping) = model.classifierRuleEditor.recoveryState else {
            return XCTFail("recovery failure must remain visible")
        }
        XCTAssertEqual(action, .restoreDefault)
        XCTAssertEqual(mapping.kind, .internal)
    }

    @MainActor
    func testCoreBridgeCreatesMissingClassifierWithoutTouchingUserBytes() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let userURL = repoURL.appendingPathComponent("notes.txt")
        let readmeURL = repoURL.appendingPathComponent("README.md")
        let areaMatrixURL = repoURL.appendingPathComponent("AREAMATRIX.md")
        try Data("user bytes".utf8).write(to: userURL)
        try Data("readme bytes".utf8).write(to: readmeURL)
        try Data("root user bytes".utf8).write(to: areaMatrixURL)
        try removeTestTemporaryItem(classifierURL(repoURL: repoURL))

        let degraded = try await bridge.listClassifierRules(repoPath: repoURL.path, editingLocale: .en)
        XCTAssertEqual(degraded.health, .missing)
        XCTAssertEqual(degraded.recoveryActions, [.createDefault])

        let restored = try await bridge.createDefaultClassifier(
            repoPath: repoURL.path,
            confirmed: true,
            editingLocale: .en
        )

        XCTAssertEqual(restored.health, .valid)
        XCTAssertEqual(try Data(contentsOf: userURL), Data("user bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: readmeURL), Data("readme bytes".utf8))
        XCTAssertEqual(try Data(contentsOf: areaMatrixURL), Data("root user bytes".utf8))
    }

    @MainActor
    func testCoreBridgeRestoreArchivesInvalidBytesWithoutOverwrite() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let invalidBytes = Data("version: [invalid".utf8)
        try invalidBytes.write(to: classifierURL(repoURL: repoURL))

        let degraded = try await bridge.listClassifierRules(repoPath: repoURL.path, editingLocale: .en)
        XCTAssertEqual(degraded.health, .invalid)
        XCTAssertTrue(degraded.recoveryActions.contains(.restoreDefault))

        let restored = try await bridge.restoreDefaultClassifier(
            repoPath: repoURL.path,
            confirmed: true,
            editingLocale: .en
        )
        let archiveURL = repoURL
            .appendingPathComponent(".areamatrix/archives/classifier", isDirectory: true)
            .appendingPathComponent("classifier.yaml.000001.bak")

        XCTAssertEqual(restored.health, .valid)
        XCTAssertEqual(try Data(contentsOf: archiveURL), invalidBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
    }

    @MainActor
    func testCoreBridgeRejectsClassifierSymlinkAndPreservesTarget() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let outsideURL = repoURL.appendingPathComponent("outside.txt")
        let outsideBytes = Data("outside bytes".utf8)
        try outsideBytes.write(to: outsideURL)
        try removeTestTemporaryItem(classifierURL(repoURL: repoURL))
        try FileManager.default.createSymbolicLink(
            at: classifierURL(repoURL: repoURL),
            withDestinationURL: outsideURL
        )

        let degraded = try await bridge.listClassifierRules(repoPath: repoURL.path, editingLocale: .en)
        XCTAssertEqual(degraded.health, .unreadable)
        XCTAssertTrue(degraded.recoveryActions.isEmpty)

        do {
            _ = try await bridge.restoreDefaultClassifier(
                repoPath: repoURL.path,
                confirmed: true,
                editingLocale: .en
            )
            XCTFail("symlink recovery must fail closed")
        } catch {
            XCTAssertEqual(try Data(contentsOf: outsideURL), outsideBytes)
        }
    }
}
