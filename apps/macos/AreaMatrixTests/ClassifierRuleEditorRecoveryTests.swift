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
            observedDisplayName: "Finance",
            displayName: "Finance Rules",
            extensions: ["pdf"],
            keywords: ["invoice"],
            previewConfirmed: true
        ))
        XCTAssertEqual(model.classifierRuleEditor.saveState, .saved("finance"))
    }

    @MainActor
    func testClassifierRuleEditorConflictPreservesDraftReviewsLatestAndRequiresSecondSave() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        var latest = ClassifierRuleEditorSnapshotState.classifierEditorFixture()
        latest.rules[1].displayNames[ClassifierEditingLocale.en.rawValue] = "Finance Latest"
        latest.rules[1].descriptions[ClassifierEditingLocale.en.rawValue] = "Saved elsewhere"
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResults: [.success(.classifierEditorFixture()), .success(latest)],
            mutationResults: [
                .failure(CoreError.Conflict(path: "classifier_rule_observed_state")),
                .success(.classifierEditorFixture(updatedRuleID: "finance"))
            ]
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )
        model.selectClassifierRule(ruleID: "finance")
        var local = try XCTUnwrap(model.classifierRuleEditor.draft)
        local.displayName = "My Local Finance"
        local.description = "My retained local description"
        model.updateClassifierRuleDraft(local)
        model.validateClassifierRuleDraft()

        let firstSaveSucceeded = await model.saveClassifierRuleDraft()
        XCTAssertFalse(firstSaveSucceeded)

        let review = try XCTUnwrap(model.classifierRuleEditor.conflictReview)
        XCTAssertEqual(review.frozenEditingLocale, .en)
        XCTAssertEqual(review.localDraft.displayName, "My Local Finance")
        XCTAssertEqual(review.latestDraft?.displayName, "Finance Latest")
        XCTAssertEqual(model.classifierRuleEditor.draft?.description, "My retained local description")
        await editor.assertClassifierRuleUpdateRequestCount(1)

        model.reviewLatestClassifierRuleConflict()

        XCTAssertNil(model.classifierRuleEditor.conflictReview)
        XCTAssertEqual(model.classifierRuleEditor.draft?.displayName, "My Local Finance")
        XCTAssertEqual(model.classifierRuleEditor.lastValidDraft?.displayName, "Finance Latest")
        XCTAssertTrue(model.classifierRuleEditor.canSave)
        await editor.assertClassifierRuleUpdateRequestCount(1)

        let secondSaveSucceeded = await model.saveClassifierRuleDraft()
        XCTAssertTrue(secondSaveSucceeded)
        let secondRequest = await editor.classifierRuleUpdateRequest(at: 1)
        XCTAssertEqual(secondRequest?.observed.displayName, "Finance Latest")
        XCTAssertEqual(secondRequest?.displayName, "My Local Finance")
        await editor.assertClassifierRuleUpdateRequestCount(2)
    }

    @MainActor
    func testClassifierRuleEditorConflictReloadDiscardsLocalDraft() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        var latest = ClassifierRuleEditorSnapshotState.classifierEditorFixture()
        latest.rules[1].displayNames[ClassifierEditingLocale.en.rawValue] = "Finance Latest"
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResults: [.success(.classifierEditorFixture()), .success(latest)],
            mutationResult: .failure(CoreError.Conflict(path: "classifier_rule_observed_state"))
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )
        model.selectClassifierRule(ruleID: "finance")
        var local = try XCTUnwrap(model.classifierRuleEditor.draft)
        local.displayName = "Discard me"
        model.updateClassifierRuleDraft(local)
        model.validateClassifierRuleDraft()

        let saveSucceeded = await model.saveClassifierRuleDraft()
        XCTAssertFalse(saveSucceeded)
        model.reloadLatestClassifierRuleConflict()

        XCTAssertNil(model.classifierRuleEditor.conflictReview)
        XCTAssertEqual(model.classifierRuleEditor.draft?.displayName, "Finance Latest")
        XCTAssertFalse(model.classifierRuleEditor.hasDirtyDraft)
        await editor.assertClassifierRuleUpdateRequestCount(1)
    }

    @MainActor
    func testClassifierRuleEditorRepositoryPolicyConflictDoesNotRetrySilently() async throws {
        let repoURL = try temporaryClassifierRecoveryRepo()
        defer { removeTestTemporaryItems(repoURL) }
        var latest = ClassifierRuleEditorSnapshotState.classifierEditorFixture()
        latest.repositoryLocalePolicy = "en"
        let editor = ClassifierSettingsRecordingRuleEditor(
            listResults: [.success(.classifierEditorFixture()), .success(latest)],
            mutationResults: [
                .failure(CoreError.Conflict(path: "repository_locale_policy")),
                .success(latest)
            ]
        )
        let model = await classifierSettingsRecoveryModel(
            repoURL: repoURL,
            predictor: ClassifierSettingsSequencePredictor(),
            editor: editor
        )
        model.selectClassifierRule(ruleID: "finance")
        var local = try XCTUnwrap(model.classifierRuleEditor.draft)
        local.displayName = "Policy conflict draft"
        model.updateClassifierRuleDraft(local)
        model.validateClassifierRuleDraft()

        let firstSaveSucceeded = await model.saveClassifierRuleDraft()

        XCTAssertFalse(firstSaveSucceeded)
        XCTAssertEqual(model.classifierRuleEditor.conflictReview?.code, "repository_locale_policy")
        XCTAssertEqual(model.classifierRuleEditor.draft?.displayName, "Policy conflict draft")
        await editor.assertClassifierRuleUpdateRequestCount(1)

        model.reviewLatestClassifierRuleConflict()
        XCTAssertEqual(model.classifierRuleEditor.repositoryLocalePolicy, "en")
        await editor.assertClassifierRuleUpdateRequestCount(1)

        let secondSaveSucceeded = await model.saveClassifierRuleDraft()
        XCTAssertTrue(secondSaveSucceeded)
        let secondRequest = await editor.classifierRuleUpdateRequest(at: 1)
        XCTAssertEqual(secondRequest?.repositoryLocalePolicy, "en")
        await editor.assertClassifierRuleUpdateRequestCount(2)
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
