@testable import AreaMatrix
import XCTest

final class ValidatePathErrorMappingTests: XCTestCase {
    @MainActor
    func testValidatePathMapsCoreFailureThroughC121ErrorMapper() async {
        let mapping = CoreErrorMappingSnapshot.errorSmokePermissionDeniedFixture(rawContext: "/tmp/repo")
        let errorMapper = ErrorSmokeRecordingErrorMapper(mapping: mapping)
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.PermissionDenied(path: "/tmp/repo"))),
            errorMapper: errorMapper,
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(errorMapper.mappedErrors, [CoreError.PermissionDenied(path: "/tmp/repo")])
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

    @MainActor
    func testConfigValidationFailureRoutesToMainRepoError() async {
        let mapping = CoreErrorMappingSnapshot.errorSmokeConfigFixture(rawContext: "schema mismatch")
        let model = OnboardingModel(
            settingsReader: ShellStaticSettingsReader(repoPath: nil),
            configLoader: ShellRecordingConfigLoader(result: .success(.shellFixture(repoPath: "/tmp/repo"))),
            pathValidator: ShellRecordingPathValidator(result: .failure(CoreError.Config(reason: "schema mismatch"))),
            errorMapper: ErrorSmokeRecordingErrorMapper(mapping: mapping),
            helpOpener: ShellNoopWelcomeHelpOpener()
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
            helpOpener: ShellNoopWelcomeHelpOpener()
        )

        model.updateRepositoryPath("/tmp/repo")
        await model.continueFromChoosePath()

        XCTAssertEqual(model.repositoryPathError, "可用空间不足，请释放空间或选择其他路径")
        XCTAssertFalse(model.canContinueFromValidatePath)
    }
}

final class QueryErrorDiagnosticSnapshotTests: XCTestCase {
    func testS205DiagnosticSnapshotPreservesCoreTokenRangeAndSuggestion() {
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

final class S307AITagSuggestionPageFeatureTests: XCTestCase {
    @MainActor
    func testS307C307AITagSuggestionSkipsDisableAllSubmitActions() {
        let states = [
            AITagSuggestionState.loaded(
                fileID: 707,
                s307AITagReport(fileID: 707, status: .skipped, skippedReason: .privacyRule),
                []
            ),
            .loaded(fileID: 708, s307AITagReport(fileID: 708, status: .noSuggestion), []),
            .loaded(fileID: 709, s307AITagReport(
                fileID: 709,
                suggestions: [s307AITagSuggestion(id: "s3-07-low", slug: "maybe", confidence: 0.55)]
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
    func testS307C307AcceptHighConfidenceExcludesPreviouslySelectedLowConfidence() {
        let report = s307AITagReport(fileID: 707, suggestions: [
            s307AITagSuggestion(id: "s3-07-finance", slug: "finance", confidence: 0.91, selectedByDefault: false),
            s307AITagSuggestion(id: "s3-07-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ])
        let lowSelected = AITagSuggestionState.loaded(fileID: 707, report, ["s3-07-low"])
        let highConfidenceOnly = AITagSuggestionAction.selectingHighConfidence(in: lowSelected)

        XCTAssertEqual(highConfidenceOnly.selectedIDs, ["s3-07-finance"])
        XCTAssertEqual(
            AITagSuggestionAction.selectedApplyItems(in: highConfidenceOnly).map(\.suggestionId),
            ["s3-07-finance"]
        )
    }

    @MainActor
    func testS307C307AITagSuggestionUsesCoreBridgeAndAppliesOnlyReviewedTags() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 707, currentName: "invoice.pdf")
        let bridge = S307AITagBridge(s307AITagReport(fileID: file.id, suggestions: [
            s307AITagSuggestion(id: "s3-07-finance", slug: "finance", confidence: 0.91),
            s307AITagSuggestion(id: "s3-07-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ]))
        let privacy = RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            tagStore: DetailTagRecordingStore(listResults: [.success(.s207Fixture(fileID: file.id, values: ["client"]))]),
            aiSettingsLoader: S307AISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: privacy,
            changeLogLister: DetailLogRecordingChangeLister(entries: [.s223Applied()]),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileTags()
        await model.loadSelectedFileAITagSuggestions()
        let undoState = await model.applySelectedFileAITagSuggestions()
        let requests = await bridge.requests()
        let privacyRequests = await privacy.requests()

        XCTAssertEqual(requests.suggest.first?.fileId, file.id)
        XCTAssertEqual(requests.suggest.first?.candidateTags, ["client"])
        XCTAssertEqual(privacyRequests.evaluations.first?.feature, .autoTags)
        XCTAssertEqual(requests.apply.first?.fileId, file.id)
        XCTAssertEqual(requests.apply.first?.confirmed, true)
        XCTAssertEqual(requests.apply.first?.callLogId, 7_707)
        XCTAssertEqual(requests.apply.first?.suggestions.map(\.suggestionId), ["s3-07-finance"])
        XCTAssertEqual(model.aiTagSuggestionState.appliedReport?.appliedCount, 1)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["finance"])
        XCTAssertNil(undoState)
    }

    @MainActor
    func testS307C307SingleRowAddImmediatelyAppliesThroughCoreBridge() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 710, currentName: "invoice-single-add.pdf")
        let bridge = S307AITagBridge(s307AITagReport(fileID: file.id, suggestions: [
            s307AITagSuggestion(id: "s3-07-finance", slug: "finance", confidence: 0.91, selectedByDefault: false),
            s307AITagSuggestion(id: "s3-07-low", slug: "maybe", confidence: 0.42, selectedByDefault: false)
        ]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            tagStore: DetailTagRecordingStore(listResults: [.success(.s207Fixture(fileID: file.id, values: []))]),
            aiSettingsLoader: S307AISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags])),
            changeLogLister: DetailLogRecordingChangeLister(entries: [.s223Applied()]),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileAITagSuggestions()
        let undoState = await model.applySelectedFileAITagSuggestion("s3-07-finance")
        let requests = await bridge.requests()

        XCTAssertEqual(model.aiTagSuggestionState.selectedIDs, [])
        XCTAssertEqual(requests.apply.count, 1)
        XCTAssertEqual(requests.apply.first?.fileId, file.id)
        XCTAssertEqual(requests.apply.first?.confirmed, true)
        XCTAssertEqual(requests.apply.first?.suggestions.map(\.suggestionId), ["s3-07-finance"])
        XCTAssertEqual(model.aiTagSuggestionState.appliedReport?.appliedCount, 1)
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), ["finance"])
        XCTAssertNil(undoState)
    }

    @MainActor
    func testS307C307RejectSelectedHidesSuggestionsAndDoesNotApply() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 713, currentName: "invoice-reject.pdf")
        let bridge = S307AITagBridge(s307AITagReport(fileID: file.id, suggestions: [
            s307AITagSuggestion(id: "s3-07-finance", slug: "finance", confidence: 0.91),
            s307AITagSuggestion(id: "s3-07-tax", slug: "tax", confidence: 0.86)
        ]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            tagStore: DetailTagRecordingStore(listResults: [.success(.s207Fixture(fileID: file.id, values: []))]),
            aiSettingsLoader: S307AISettingsLoader(),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags])),
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileTags()
        await model.loadSelectedFileAITagSuggestions()
        model.clearSelectedFileAITagSuggestions()
        let requests = await bridge.requests()

        XCTAssertEqual(model.aiTagSuggestionState.report?.suggestions, [])
        XCTAssertEqual(model.aiTagSuggestionState.selectedIDs, [])
        XCTAssertEqual(model.aiTagSuggestionState.rejectedFeedback?.rejectedIDs, ["s3-07-finance", "s3-07-tax"])
        XCTAssertEqual(
            model.aiTagSuggestionState.rejectedFeedback?.message,
            "2 suggestions rejected. Feedback recorded for this review."
        )
        XCTAssertEqual(requests.apply, [])
        XCTAssertEqual(model.detailTagEditorState.tagSet?.fileTags.map(\.value), [])
    }

    @MainActor
    func testS307C307AITagSuggestionOffDoesNotEvaluatePrivacyOrGenerateTags() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 711, currentName: "invoice-ai-off.pdf")
        let bridge = S307AITagBridge(s307AITagReport(fileID: file.id))
        let privacy = RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags]))
        let settings = S307AISettingsLoader(aiEnabled: false)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            aiSettingsLoader: settings,
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: privacy,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileAITagSuggestions()
        let bridgeRequests = await bridge.requests()
        let privacyRequests = await privacy.requests()
        let settingsRequests = await settings.requests()

        XCTAssertEqual(settingsRequests, ["/tmp/repo"])
        XCTAssertEqual(bridgeRequests.suggest, [])
        XCTAssertEqual(bridgeRequests.apply, [])
        XCTAssertEqual(privacyRequests.loadCount, 0)
        XCTAssertEqual(privacyRequests.evaluations, [])
        XCTAssertEqual(model.aiTagSuggestionState.report?.status, .skipped)
        XCTAssertEqual(model.aiTagSuggestionState.report?.skippedReason, .aiDisabled)
        XCTAssertEqual(model.aiTagSuggestionState.report?.contentsRead, false)
        XCTAssertEqual(model.aiTagSuggestionState.report?.aiUsed, false)
        XCTAssertEqual(model.aiTagSuggestionState.report?.networkUsed, false)
    }

    @MainActor
    func testS307C307AutoTagsOffDoesNotEvaluatePrivacyOrGenerateTags() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 712, currentName: "invoice-auto-tags-off.pdf")
        let bridge = S307AITagBridge(s307AITagReport(fileID: file.id))
        let privacy = RemotePrivacyRulesBridge(snapshot: .s303PrivacyRules(featureScope: [.autoTags]))
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            aiSettingsLoader: S307AISettingsLoader(autoTagsEnabled: false),
            aiTagSuggestionStore: bridge,
            aiPrivacyRules: privacy,
            errorMapper: DetailMetaErrorMapper(mapping: .s207TagDb())
        )

        await model.selectFiles([file.id])
        await model.loadSelectedFileAITagSuggestions()
        let bridgeRequests = await bridge.requests()
        let privacyRequests = await privacy.requests()

        XCTAssertEqual(bridgeRequests.suggest, [])
        XCTAssertEqual(bridgeRequests.apply, [])
        XCTAssertEqual(privacyRequests.loadCount, 0)
        XCTAssertEqual(privacyRequests.evaluations, [])
        XCTAssertEqual(model.aiTagSuggestionState.report?.status, .skipped)
        XCTAssertEqual(model.aiTagSuggestionState.report?.skippedReason, .featureDisabled)
        XCTAssertEqual(model.aiTagSuggestionState.report?.contentsRead, false)
        XCTAssertEqual(model.aiTagSuggestionState.report?.aiUsed, false)
    }
}

private final class ErrorSmokeRecordingErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private(set) var mappedErrors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        mappedErrors.append(error)
        return mapping
    }
}

private extension CoreErrorMappingSnapshot {
    static func errorSmokePermissionDeniedFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .permissionDenied,
            userMessage: "无访问权限",
            severity: .high,
            suggestedAction: "请在系统设置中授予权限，或选择其他资料库位置",
            recoverability: .userActionRequired,
            rawContext: rawContext
        )
    }

    static func errorSmokeConfigFixture(rawContext: String) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "资料库 schema 不兼容",
            severity: .critical,
            suggestedAction: "请选择其他资料库，或导出诊断信息",
            recoverability: .fatal,
            rawContext: rawContext
        )
    }
}
