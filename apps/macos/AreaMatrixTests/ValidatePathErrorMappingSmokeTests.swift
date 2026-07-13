@testable import AreaMatrix
import XCTest

final class ValidatePathErrorMappingTests: XCTestCase {
    @MainActor
    func testValidatePathMapsCoreFailureThroughErrorMappingCoreErrorMapper() async {
        let mapping = CoreErrorMappingSnapshot.errorSmokePermissionDeniedFixture(rawContext: "/tmp/repo")
        let errorMapper = StaticCoreErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))),
            errorMapper: errorMapper,
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        await errorMapper.assertMappedCoreErrors([CoreError.PermissionDenied(path: "/tmp/repo")])
        XCTAssertEqual(model.repositoryPathError, "无访问权限")
        XCTAssertEqual(model.repositoryPathErrorMapping, mapping)
        XCTAssertFalse(model.canContinueFromValidatePath)
    }

    func testCoreBridgeMapsCoreErrorThroughGeneratedBindings() async {
        let mapping = await CoreBridge().mapCoreError(CoreError.PermissionDenied(path: "/restricted/repo"))

        XCTAssertEqual(mapping.kind, .permissionDenied)
        XCTAssertEqual(mapping.userMessage, "无访问权限")
        XCTAssertEqual(mapping.severity, .high)
        XCTAssertEqual(mapping.recoverability, .userActionRequired)
        XCTAssertEqual(mapping.rawContext, "/restricted/repo")
        XCTAssertFalse(mapping.suggestedAction.isEmpty)
    }

    func testAppSemanticErrorMappingBypassesCoreErrorRecording() async {
        let mapping = CoreErrorMappingSnapshot.invalidPath(rawContext: "app-semantic-path")
        let errorMapper = StaticCoreErrorMapper(mapping: .errorSmokePermissionDeniedFixture(rawContext: "unexpected"))
        let error = AppSemanticError(appErrorMapping: mapping)

        let mappedError = await errorMapper.mapError(error)
        let knownMapping = await errorMapper.mapKnownErrorIfPresent(error)

        XCTAssertEqual(mappedError, mapping)
        XCTAssertEqual(knownMapping, mapping)
        XCTAssertEqual(error.localizedDescription, "app-semantic-path")
        await errorMapper.assertMappedCoreErrors([])
        XCTAssertNil(CoreErrorRawContextSnapshot(error))
    }

    @MainActor
    func testConfigValidationFailureRoutesToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.errorSmokeConfigFixture(rawContext: "schema mismatch")
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.Config(reason: "schema mismatch"))),
            errorMapper: StaticCoreErrorMapper(mapping: mapping),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.route, .mainRepoError("/tmp/repo", mapping))
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

final class ValidatePathIntegrationSmokeTests: XCTestCase {
    @MainActor
    func testInsufficientCapacityBlocksValidatePathContinue() async {
        let validation = RepoPathValidationSnapshot.shellFixture(
            repoPath: "/tmp/repo",
            availableCapacityBytes: 128 * 1024 * 1024
        )
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .success(validation)),
            helpOpener: NoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "可用空间不足，请释放空间或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

final class QueryErrorDiagnosticSnapshotTests: XCTestCase {
    func testQueryErrorDiagnosticSnapshotPreservesCoreTokenRangeAndSuggestion() {
        let diagnostic = SearchQueryDiagnostic(
            kind: .unknownField,
            severity: .error,
            message: "Unknown field `kindd`",
            token: "kindd",
            start: 0,
            end: 5,
            suggestion: "kind"
        )
        let snapshot = SearchQueryDiagnosticSnapshot(coreDiagnostic: diagnostic)

        XCTAssertEqual(snapshot.kindDisplayName, "Unknown field")
        XCTAssertEqual(snapshot.severityDisplayName, "Error")
        XCTAssertEqual(snapshot.token, "kindd")
        XCTAssertEqual(snapshot.start, 0)
        XCTAssertEqual(snapshot.end, 5)
        XCTAssertEqual(snapshot.suggestion, "kind")
        XCTAssertEqual(snapshot.problemAccessibilityHint, "Token kindd. Position 0-5. Suggestion kind")
    }
}

final class AITagSuggestionPageFeatureTests: XCTestCase {
    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreAITagSuggestionSkipsDisableAllSubmitActions() {
        let states = [
            AITagSuggestionState.loaded(
                fileID: 707,
                aiTagSuggestionAITagReport(fileID: 707, status: .skipped, skippedReason: .privacyRule),
                []
            ),
            .loaded(fileID: 708, aiTagSuggestionAITagReport(fileID: 708, status: .noSuggestion), []),
            .loaded(fileID: 709, aiTagSuggestionAITagReport(
                fileID: 709,
                suggestions: [aiTagSuggestionAITagSuggestion(id: "ai-tag-low", slug: "maybe", confidence: 0.55)]
            ), [])
        ]

        for state in states {
            XCTAssertFalse(state.hasHighConfidenceApplyCandidates)
            XCTAssertFalse(state.canApplySelectedSuggestions)
            XCTAssertFalse(state.canEditSelectedSuggestions)
            XCTAssertEqual(AITagSuggestionAction.selectedApplyItems(in: state), [])
        }
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreAcceptHighConfidenceExcludesPreviouslySelectedLowConfidence() {
        let report = aiTagSuggestionAITagReport(fileID: 707, suggestions: [
            aiTagSuggestionAITagSuggestion(
                id: "ai-tag-finance",
                slug: "finance",
                confidence: 0.91,
                selectedByDefault: false
            ),
            aiTagSuggestionAITagSuggestion(id: "ai-tag-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ])
        let lowSelected = AITagSuggestionState.loaded(fileID: 707, report, ["ai-tag-low"])
        let highConfidenceOnly = AITagSuggestionAction.selectingHighConfidence(in: lowSelected)

        XCTAssertEqual(highConfidenceOnly.selectedIDs, ["ai-tag-finance"])
        XCTAssertEqual(
            AITagSuggestionAction.selectedApplyItems(in: highConfidenceOnly).map(\.suggestionId),
            ["ai-tag-finance"]
        )
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreAITagSuggestionUsesCoreBridgeAndAppliesOnlyReviewedTags() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 707, currentName: "invoice.pdf")
        let bridge = AITagSuggestionAITagBridge(aiTagSuggestionAITagReport(fileID: file.id, suggestions: [
            aiTagSuggestionAITagSuggestion(id: "ai-tag-finance", slug: "finance", confidence: 0.91),
            aiTagSuggestionAITagSuggestion(id: "ai-tag-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ]))
        let privacy = RemotePrivacyRulesBridge(snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            tagStore: DetailTagRecordingStore(listResults: [.success(.tagAddFixture(
                fileID: file.id,
                values: ["client"]
            ))]),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: privacy,
            changeLogLister: DetailLogRecordingChangeLister(entries: [.tagSuggestionsApplied()]),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileTags()
        await model.loadSelectedFileAITagSuggestions()
        let undoState = await model.applySelectedFileAITagSuggestions()

        await bridge.assertSingleSuggestRequest(fileID: file.id, candidateTags: ["client"])
        await privacy.assertEvaluation(at: 0, feature: .autoTags)
        await bridge.assertSingleApplyRequest(
            fileID: file.id,
            confirmed: true,
            callLogID: 7707,
            suggestionIDs: ["ai-tag-finance"]
        )
        XCTAssertEqual(model.aiTagSuggestionState.appliedReport?.appliedCount, 1)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["finance"])
        XCTAssertNil(undoState)
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreSingleRowAddImmediatelyAppliesThroughCoreBridge() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 710, currentName: "invoice-single-add.pdf")
        let bridge = AITagSuggestionAITagBridge(aiTagSuggestionAITagReport(fileID: file.id, suggestions: [
            aiTagSuggestionAITagSuggestion(
                id: "ai-tag-finance",
                slug: "finance",
                confidence: 0.91,
                selectedByDefault: false
            ),
            aiTagSuggestionAITagSuggestion(id: "ai-tag-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            tagStore: DetailTagRecordingStore(listResults: [.success(.tagAddFixture(fileID: file.id, values: []))]),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            changeLogLister: DetailLogRecordingChangeLister(entries: [.tagSuggestionsApplied()]),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileAITagSuggestions()
        let undoState = await model.applySelectedFileAITagSuggestion("ai-tag-finance")

        XCTAssertEqual(model.aiTagSuggestionState.selectedIDs, [])
        await bridge.assertSingleApplyRequest(fileID: file.id, confirmed: true, suggestionIDs: ["ai-tag-finance"])
        XCTAssertEqual(model.aiTagSuggestionState.appliedReport?.appliedCount, 1)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["finance"])
        XCTAssertNil(undoState)
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreRejectSelectedHidesSuggestionsAndDoesNotApply() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 713, currentName: "invoice-reject.pdf")
        let bridge = AITagSuggestionAITagBridge(aiTagSuggestionAITagReport(fileID: file.id, suggestions: [
            aiTagSuggestionAITagSuggestion(id: "ai-tag-finance", slug: "finance", confidence: 0.91),
            aiTagSuggestionAITagSuggestion(id: "ai-tag-tax", slug: "tax", confidence: 0.86)
        ]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            tagStore: DetailTagRecordingStore(listResults: [.success(.tagAddFixture(fileID: file.id, values: []))]),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(
                snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags])
            ),
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileTags()
        await model.loadSelectedFileAITagSuggestions()
        model.clearSelectedFileAITagSuggestions()

        XCTAssertEqual(model.aiTagSuggestionState.report?.suggestions, [])
        XCTAssertEqual(model.aiTagSuggestionState.selectedIDs, [])
        XCTAssertEqual(model.aiTagSuggestionState.rejectedFeedback?.rejectedIDs, ["ai-tag-finance", "ai-tag-tax"])
        XCTAssertEqual(
            model.aiTagSuggestionState.rejectedFeedback?.message,
            "2 suggestions rejected. Feedback recorded for this review."
        )
        await bridge.assertNoAITagSuggestionApplyRequests()
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), [])
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreAITagSuggestionOffDoesNotEvaluatePrivacyOrGenerateTags() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 711, currentName: "invoice-ai-off.pdf")
        let bridge = AITagSuggestionAITagBridge(aiTagSuggestionAITagReport(fileID: file.id))
        let privacy = RemotePrivacyRulesBridge(snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags]))
        let settings = AITagSuggestionAISettingsLoader(aiEnabled: false)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            aiSettingsLoader: settings,
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: privacy,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileAITagSuggestions()

        await settings.assertRequestedRepoPaths(["/tmp/repo"])
        await bridge.assertNoAITagSuggestionRequests()
        await privacy.assertLoadCount(0)
        await privacy.assertNoEvaluations()
        XCTAssertEqual(model.aiTagSuggestionState.report?.status, .skipped)
        XCTAssertEqual(model.aiTagSuggestionState.report?.skippedReason, .aiDisabled)
        XCTAssertEqual(model.aiTagSuggestionState.report?.contentsRead, false)
        XCTAssertEqual(model.aiTagSuggestionState.report?.aiUsed, false)
        XCTAssertEqual(model.aiTagSuggestionState.report?.networkUsed, false)
    }

    @MainActor
    func testAITagSuggestionAITagsSuggestionCoreAutoTagsOffDoesNotEvaluatePrivacyOrGenerateTags() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 712, currentName: "invoice-auto-tags-off.pdf")
        let bridge = AITagSuggestionAITagBridge(aiTagSuggestionAITagReport(fileID: file.id))
        let privacy = RemotePrivacyRulesBridge(snapshot: .remoteProviderConfigPrivacyRules(featureScope: [.autoTags]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            aiSettingsLoader: AITagSuggestionAISettingsLoader(autoTagsEnabled: false),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: privacy,
            errorMapper: StaticCoreErrorMapper(mapping: .tagAddTagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileAITagSuggestions()

        await bridge.assertNoAITagSuggestionRequests()
        await privacy.assertLoadCount(0)
        await privacy.assertNoEvaluations()
        XCTAssertEqual(model.aiTagSuggestionState.report?.status, .skipped)
        XCTAssertEqual(model.aiTagSuggestionState.report?.skippedReason, .featureDisabled)
        XCTAssertEqual(model.aiTagSuggestionState.report?.contentsRead, false)
        XCTAssertEqual(model.aiTagSuggestionState.report?.aiUsed, false)
    }
}

private extension CoreErrorMappingSnapshot {
    static func errorSmokePermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func errorSmokeConfigFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .config,
            userMessage: "资料库 schema 不兼容",
            severity: .critical,
            suggestedAction: "请选择其他资料库，或导出诊断信息",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }
}
