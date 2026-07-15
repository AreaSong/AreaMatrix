@testable import AreaMatrix
import XCTest

final class ClassifierRuleEditorRecoveryTests: XCTestCase {
    @MainActor
    func testClassifierRuleEditorLoadFailureDoesNotCreateSaveFailure() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .failure(CoreError.Config(reason: "classifier list unavailable"))
        )

        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )

        guard case .failed = model.classifierRuleEditor.loadState else {
            return XCTFail("load failure must remain in the load recovery state")
        }
        XCTAssertEqual(model.classifierRuleEditor.saveState, .idle)
    }

    @MainActor
    func testClassifierRuleEditorSaveFailureKeepsLoadedDraftAndAvoidsLoadFailure() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResult: .success(.classifierEditorFixture()),
            mutationResult: .failure(CoreError.Config(reason: "classifier save unavailable"))
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )
        model.selectClassifierRule(ruleID: "finance")
        var draft = try XCTUnwrap(model.classifierRuleEditor.draft)
        draft.displayName = "Finance Retry Draft"
        model.updateClassifierRuleDraft(draft)
        model.validateClassifierRuleDraft()

        await model.saveClassifierRuleDraft()

        XCTAssertEqual(model.classifierRuleEditor.loadState, .loaded)
        guard case .failed = model.classifierRuleEditor.saveState else {
            return XCTFail("save failure must remain in the save recovery state")
        }
        XCTAssertEqual(model.classifierRuleEditor.draft?.displayName, "Finance Retry Draft")
        XCTAssertTrue(model.classifierRuleEditor.hasDirtyDraft)
    }

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

        await editor.assertClassifierRuleListRequests([repoURL.path])
        await editor.assertSingleClassifierRuleUpdateRequest(.init(
            repoPath: repoURL.path,
            ruleID: "finance",
            displayName: "Finance Rules",
            extensions: ["pdf"],
            keywords: ["invoice"],
            previewConfirmed: true
        ))
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

        await editor.assertSingleClassifierRuleCreateRequest(
            repoPath: repoURL.path,
            slug: "tax",
            displayName: "Tax",
            extensions: ["pdf"],
            namingTemplate: "{stem}-{date}"
        )
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
        await editor.assertNoClassifierRuleDeleteRequests()

        await model.confirmDeleteSelectedClassifierRule()

        await editor.assertSingleClassifierRuleDeleteRequest(
            repoPath: repoURL.path,
            ruleID: "finance",
            replacementCategory: "docs",
            previewConfirmed: true
        )
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
