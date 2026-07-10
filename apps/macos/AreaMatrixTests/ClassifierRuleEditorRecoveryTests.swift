@testable import AreaMatrix
import XCTest

final class ClassifierRuleEditorRecoveryTests: XCTestCase {
    @MainActor
    func testClassifierRuleEditorRuleEditorUpdatesExistingRuleThroughCoreCrudAfterValidation() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierEditorFixture()),
            mutationResult: .success(.classifierEditorFixture(updatedRuleID: "finance"))
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.selectClassifierRule(ruleID: "finance")
        var draft = try XCTUnwrap(model.classifierRuleEditor.draft)
        draft.displayName = "Finance Rules"
        model.updateClassifierRuleDraft(draft)
        model.addClassifierRuleExtension(".PDF")
        model.addClassifierRuleKeyword("invoice")

        XCTAssertFalse(model.classifierRuleEditor.canSave)
        model.validateClassifierRuleDraft()
        XCTAssertTrue(model.classifierRuleEditor.canSave)

        await model.saveClassifierRuleDraft()

        let updates = await editor.updateRequests()
        await editor.assertListRequests([repoURL.path])
        XCTAssertEqual(updates.first?.repoPath, repoURL.path)
        XCTAssertEqual(updates.first?.request.ruleID, "finance")
        XCTAssertEqual(updates.first?.request.displayName, "Finance Rules")
        XCTAssertEqual(updates.first?.request.extensions, ["pdf"])
        XCTAssertEqual(updates.first?.request.keywords, ["invoice"])
        XCTAssertTrue(updates.first?.request.previewConfirmed ?? false)
        XCTAssertEqual(model.classifierRuleEditor.saveState, .saved("finance"))
    }

    @MainActor
    func testClassifierRuleEditorNewCategoryUsesCreateCrudAndRequiresValidate() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierEditorFixture()),
            mutationResult: .success(.classifierEditorFixture(updatedRuleID: "tax"))
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.createClassifierRule()
        var draft = try XCTUnwrap(model.classifierRuleEditor.draft)
        draft.slug = "tax"
        draft.displayName = "Tax"
        draft.description = "Tax documents"
        draft.priority = 10
        draft.namingTemplate = "{stem}-{date}"
        model.updateClassifierRuleDraft(draft)
        model.addClassifierRuleExtension("pdf")

        XCTAssertFalse(model.classifierRuleEditor.canSave)
        model.validateClassifierRuleDraft()
        await model.saveClassifierRuleDraft()

        let creates = await editor.createRequests()
        XCTAssertEqual(creates.first?.request.slug, "tax")
        XCTAssertEqual(creates.first?.request.displayName, "Tax")
        XCTAssertEqual(creates.first?.request.extensions, ["pdf"])
        XCTAssertEqual(creates.first?.request.namingTemplate, "{stem}-{date}")
    }

    @MainActor
    func testClassifierRuleEditorDeleteRuleUsesCrudWithoutMovingHistoricalFiles() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierEditorFixture()),
            mutationResult: .success(.classifierEditorFixture(updatedRuleID: "docs"))
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.selectClassifierRule(ruleID: "finance")
        model.requestDeleteSelectedClassifierRule()
        var deletes = await editor.deleteRequests()
        XCTAssertTrue(deletes.isEmpty)

        await model.confirmDeleteSelectedClassifierRule()

        deletes = await editor.deleteRequests()
        XCTAssertEqual(deletes.first?.repoPath, repoURL.path)
        XCTAssertEqual(deletes.first?.request.ruleID, "finance")
        XCTAssertEqual(deletes.first?.request.replacementCategory, "docs")
        XCTAssertTrue(deletes.first?.request.previewConfirmed ?? false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("README.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("AREAMATRIX.md").path))
    }

    @MainActor
    func testClassifierRuleEditorRemovingMatcherRequiresImpactSummaryBeforeSave() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(listResult: .success(.classifierEditorFixture()))
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        model.selectClassifierRule(ruleID: "finance")
        model.requestRemoveClassifierRuleExtension("pdf")
        model.validateClassifierRuleDraft()

        XCTAssertFalse(model.classifierRuleEditor.canSave)
        XCTAssertNotNil(model.classifierRuleEditor.pendingMatcherRemoval)
        XCTAssertEqual(model.classifierRuleEditor.draft?.extensions, ["pdf"])

        model.confirmClassifierRuleImpactSummary()
        model.validateClassifierRuleDraft()

        XCTAssertTrue(model.classifierRuleEditor.canSave)
        XCTAssertNil(model.classifierRuleEditor.pendingMatcherRemoval)
        XCTAssertEqual(model.classifierRuleEditor.draft?.extensions, [])
    }
}
