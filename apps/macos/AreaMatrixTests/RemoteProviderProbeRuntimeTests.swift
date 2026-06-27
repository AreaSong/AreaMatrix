@testable import AreaMatrix
import Foundation
import XCTest

// swiftlint:disable:next type_body_length
final class RemoteProviderProbeRuntimeTests: XCTestCase {
    @MainActor
    func testCoreBridgeUsesInstalledRuntimeForKeychainReferenceProviderProbe() async throws {
        let runtime = try ProbeRuntimeRecorder()
        let environment = ProbeRuntimeEnvironment(
            runtimePath: runtime.runtimeURL.path,
            evidencePath: runtime.evidenceURL.path
        )
        environment.install()
        defer { environment.restore() }

        let repoURL = try makeRemoteProviderProbeTemporaryRepoURL()
        defer { removeTestTemporaryItems(repoURL) }
        try initRepo(repoPath: repoURL.path, options: RepoInitOptions(
            mode: .createEmpty,
            createDefaultCategories: false,
            overviewOutput: .generatedOnly
        ))
        let keyReference = "keychain:remote-ai-other-runtime-test"

        let bridge = CoreBridge()
        let testResult = try await bridge.testRemoteProvider(
            repoPath: repoURL.path,
            request: RemoteProviderTestRequestState(
                provider: .other,
                modelID: "gpt-4.1-mini",
                endpointURL: runtime.endpointURL,
                keyReference: keyReference
            )
        )

        let verificationToken = try XCTUnwrap(testResult.verificationToken)
        let enableSnapshot = try await bridge.enableRemoteProvider(
            repoPath: repoURL.path,
            request: RemoteProviderEnableRequestState(
                provider: .other,
                modelID: "gpt-4.1-mini",
                endpointURL: runtime.endpointURL,
                keyReference: keyReference,
                featureScope: [.autoSummaries],
                verificationToken: verificationToken,
                dataFlowConfirmed: true
            )
        )

        XCTAssertEqual(testResult.status, .succeeded)
        XCTAssertTrue(testResult.providerVerified)
        XCTAssertTrue(enableSnapshot.remoteProviderEnabled)
        let evidence = try runtime.evidence()
        XCTAssertTrue(evidence.contains("provider=Other"))
        XCTAssertTrue(evidence.contains("url=\(runtime.endpointURL)"))
        XCTAssertTrue(evidence.contains("key_reference=\(keyReference)"))
        XCTAssertTrue(evidence.contains("credential_reference_shape=keychain"))
    }

    func testInstallerRegistersExecutableCredentialBackedRuntime() throws {
        let environment = ProbeRuntimeEnvironment(runtimePath: nil, evidencePath: nil)
        environment.clearRuntime()
        defer { environment.restore() }
        let installer = RemoteProviderProbeRuntimeInstaller()
        let runtimePath = try installer.ensureInstalled()

        let attributes = try FileManager.default.attributesOfItem(atPath: runtimePath)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? Int)
        let script = try String(contentsOfFile: runtimePath, encoding: .utf8)
        let installedPath = environmentString(RemoteProviderProbeRuntimeInstaller.environmentKey)
        XCTAssertEqual(installedPath, runtimePath)
        XCTAssertEqual(permissions & 0o111, 0o100)
        XCTAssertTrue(script.contains("/usr/bin/security find-generic-password"))
        XCTAssertTrue(script.contains("Authorization: Bearer %s"))
        XCTAssertTrue(script.contains("x-api-key: %s"))
        XCTAssertTrue(script.contains("$credential"))
        XCTAssertFalse(script.contains("Authorization: Bearer %s\"\\n' \"$key_reference\""))
        XCTAssertFalse(script.contains("x-api-key: %s\"\\n' \"$key_reference\""))
    }

    @MainActor
    func testAICategorySuggestionAskSuggestionUsesAIClassificationSuggestionCoreBridgeAndKeepsDraftPending() async {
        let request = AIClassificationSuggestionRequestState(
            fileID: 404,
            contextPolicy: .limitedTextSummary,
            privacyPolicyRef: "privacy-v1"
        )
        let bridge =
            AICategorySuggestionSuggestionBridge(result: .success(.aiCategorySuggestionSuggested(fileID: request
                    .fileID)))
        let model = aiCategorySuggestionSuggestionModel(request: request, bridge: bridge)

        await model.askForSuggestion()
        let recordedRequests = await bridge.recordedRequests()

        XCTAssertEqual(recordedRequests, [request])
        XCTAssertEqual(model.statusText, "AI suggested a category.")
        XCTAssertEqual(model.suggestion?.suggestedCategory, "finance/invoices")
        XCTAssertEqual(model.suggestion?.usedContext, [.fileName, .extension, .repoRelativePath])
        XCTAssertEqual(model.suggestion?.callLogID, 304)
        XCTAssertNil(model.acceptDisabledReason)
    }

    @MainActor
    func testAICategorySuggestionPrivacySkipMapsToDisabledAcceptState() async {
        let request = AIClassificationSuggestionRequestState(fileID: 405, contextPolicy: .fileNameAndPath)
        let bridge =
            AICategorySuggestionSuggestionBridge(result: .success(.aiCategorySuggestionPrivacySkipped(fileID: request
                    .fileID)))
        let fallbackBridge =
            AICategorySuggestionFallbackBridge(status: .aiCategorySuggestionPrivacySkipped(callLogID: 305))
        let model = aiCategorySuggestionSuggestionModel(
            request: request,
            bridge: bridge,
            fallbackBridge: fallbackBridge
        )

        await model.askForSuggestion()
        let fallbackRequests = await fallbackBridge.recordedRequests()

        XCTAssertEqual(fallbackRequests.first?.operation, .classificationSuggestion)
        XCTAssertEqual(fallbackRequests.first?.privacyDecision, .skipped)
        XCTAssertEqual(fallbackRequests.first?.privacySkippedReason, .privacyRule)
        XCTAssertEqual(fallbackRequests.first?.categorySkippedReason, .privacyRule)
        XCTAssertEqual(fallbackRequests.first?.callLogStatus, .skipped)
        XCTAssertEqual(model.statusText, "Skipped by privacy rule")
        XCTAssertEqual(model.acceptDisabledReason, "Skipped by privacy rule.")
        XCTAssertEqual(model.suggestion?.privacyRuleID, "rule-confidential")
        XCTAssertEqual(model.suggestion?.usedContext, [])
        XCTAssertEqual(model.fallbackStatus?.nonAiFallbackAction, .classifyManually)
    }

    @MainActor
    func testAICategorySuggestionPrivacySkippedPanelOffersAIPrivacyRulesCorePrivacyRuleReferenceAction() async {
        let request = AIClassificationSuggestionRequestState(fileID: 407, contextPolicy: .fileNameAndPath)
        let bridge =
            AICategorySuggestionSuggestionBridge(result: .success(.aiCategorySuggestionPrivacySkipped(fileID: request
                    .fileID)))
        let fallbackBridge =
            AICategorySuggestionFallbackBridge(status: .aiCategorySuggestionPrivacySkipped(callLogID: 305))
        let model = aiCategorySuggestionSuggestionModel(
            request: request,
            bridge: bridge,
            fallbackBridge: fallbackBridge
        )

        await model.askForSuggestion()
        let panel = AIClassificationSuggestionPanel(
            model: model,
            fileName: "confidential.pdf",
            currentPath: "inbox/confidential.pdf"
        )

        XCTAssertEqual(model.fallbackStatus?.kind, .privacySkipped)
        XCTAssertEqual(model.fallbackStatus?.primaryAction, .viewPrivacyRule)
        XCTAssertEqual(model.fallbackStatus?.secondaryAction, .viewCallLog)
        XCTAssertEqual(model.fallbackStatus?.nonAiFallbackAction, .classifyManually)
        assertTestMirrorDescription(of: panel.body, contains: [
            "Skipped by privacy rule",
            "View privacy rule",
            "Classify manually"
        ], maxDepth: 8)
        XCTAssertFalse(panel.isFallbackActionDisabled(.viewPrivacyRule))
    }

    @MainActor
    func testAICategorySuggestionProviderUnavailableUsesAIFallbackCoreRetryableFallbackStatus() async {
        let request = AIClassificationSuggestionRequestState(fileID: 408, contextPolicy: .fileNameOnly)
        let fallbackBridge =
            AICategorySuggestionFallbackBridge(status: .aiCategorySuggestionProviderUnavailable(callLogID: 306))
        let model = aiCategorySuggestionSuggestionModel(
            request: request,
            bridge: AICategorySuggestionSuggestionBridge(
                result: .success(.aiCategorySuggestionProviderUnavailable(fileID: request
                        .fileID))
            ),
            fallbackBridge: fallbackBridge
        )

        await model.askForSuggestion()
        let fallbackRequests = await fallbackBridge.recordedRequests()

        XCTAssertEqual(fallbackRequests.first?.providerError, .providerUnavailable)
        XCTAssertEqual(fallbackRequests.first?.providerErrorCode, "ProviderUnavailable")
        XCTAssertEqual(fallbackRequests.first?.callLogStatus, .unavailable)
        XCTAssertEqual(model.statusText, "AI provider is unavailable")
        XCTAssertEqual(model.acceptDisabledReason, "Retry before accepting this suggestion.")
        XCTAssertEqual(model.fallbackStatus?.retryable, true)
    }

    @MainActor
    func testAIFallbackAIClassificationSuggestionCoreFallbackRegionUsesClassificationSuggestionStatusOnly() async {
        let request = AIClassificationSuggestionRequestState(fileID: 410, contextPolicy: .fileNameOnly)
        let fallbackBridge =
            AICategorySuggestionFallbackBridge(status: .aiCategorySuggestionProviderUnavailable(callLogID: 731))
        let model = aiCategorySuggestionSuggestionModel(
            request: request,
            bridge: AICategorySuggestionSuggestionBridge(
                result: .success(.aiCategorySuggestionProviderUnavailable(fileID: request
                        .fileID))
            ),
            fallbackBridge: fallbackBridge
        )
        let panel = AIClassificationSuggestionPanel(
            model: model,
            fileName: "invoice.pdf",
            currentPath: "inbox/invoice.pdf"
        )

        await model.askForSuggestion()
        let fallbackRequests = await fallbackBridge.recordedRequests()

        XCTAssertEqual(fallbackRequests.first?.operation, .classificationSuggestion)
        XCTAssertEqual(fallbackRequests.first?.semanticFallbackReason, nil)
        XCTAssertEqual(model.fallbackStatus?.kind, .providerUnavailable)
        XCTAssertEqual(model.fallbackStatus?.primaryAction, .retry)
        XCTAssertEqual(model.fallbackStatus?.secondaryAction, .viewCallLog)
        XCTAssertEqual(model.fallbackStatus?.nonAiFallbackAction, .classifyManually)
        assertTestMirrorDescription(of: panel.body, contains: [
            "Retry",
            "Classify manually"
        ], maxDepth: 8)
        XCTAssertFalse(panel.isFallbackActionDisabled(.retry))
        XCTAssertFalse(panel.isFallbackActionDisabled(.viewCallLog))
        XCTAssertNotEqual(model.fallbackStatus?.primaryAction, .buildSemanticIndex)
        XCTAssertNotEqual(model.fallbackStatus?.nonAiFallbackAction, .useNormalSearch)
    }

    @MainActor
    func testAICategorySuggestionStandardAIFallbackCoreRecoveryActionsAreVisibleAndTriggerable() {
        let model = aiCategorySuggestionSuggestionModel(
            request: AIClassificationSuggestionRequestState(fileID: 409, contextPolicy: .fileNameOnly),
            bridge: AICategorySuggestionSuggestionBridge(
                result: .success(.aiCategorySuggestionProviderUnavailable(fileID: 409))
            )
        )
        var openedAISettings = false
        var openedLocalModelStatus = false
        var configuredRemoteAI = false
        let panel = AIClassificationSuggestionPanel(
            model: model,
            fileName: "invoice.pdf",
            currentPath: "inbox/invoice.pdf",
            onOpenAISettings: { openedAISettings = true },
            onOpenLocalModelStatus: { openedLocalModelStatus = true },
            onConfigureRemoteAI: { configuredRemoteAI = true }
        )

        XCTAssertFalse(panel.isFallbackActionDisabled(.openAiSettings))
        XCTAssertFalse(panel.isFallbackActionDisabled(.openLocalModelStatus))
        XCTAssertFalse(panel.isFallbackActionDisabled(.configureRemoteAi))

        panel.performFallbackAction(.openAiSettings)
        panel.performFallbackAction(.openLocalModelStatus)
        panel.performFallbackAction(.configureRemoteAi)

        XCTAssertTrue(openedAISettings)
        XCTAssertTrue(openedLocalModelStatus)
        XCTAssertTrue(configuredRemoteAI)
    }

    @MainActor
    func testAICategorySuggestionAIFallbackCoreViewCallLogActionUsesFallbackCallLogID() async {
        let fallbackBridge =
            AICategorySuggestionFallbackBridge(status: .aiCategorySuggestionProviderUnavailable(callLogID: 730))
        let model = aiCategorySuggestionSuggestionModel(
            request: AIClassificationSuggestionRequestState(fileID: 409, contextPolicy: .fileNameOnly),
            bridge: AICategorySuggestionSuggestionBridge(
                result: .success(.aiCategorySuggestionProviderUnavailable(fileID: 409))
            ),
            fallbackBridge: fallbackBridge
        )
        var viewedCallLogID: Int64?
        let panel = AIClassificationSuggestionPanel(
            model: model,
            fileName: "invoice.pdf",
            currentPath: "inbox/invoice.pdf",
            onViewCall: { viewedCallLogID = $0 }
        )

        await model.askForSuggestion()
        XCTAssertFalse(panel.isFallbackActionDisabled(.viewCallLog))
        panel.performFallbackAction(.viewCallLog)

        XCTAssertEqual(viewedCallLogID, 730)
    }

    @MainActor
    func testAICategorySuggestionPageIntegrationKeepsSuggestionDraftUntilClassifierExit() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 304, currentName: "invoice.pdf")
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )
        let request = AIClassificationSuggestionRequestState(
            fileID: file.id,
            contextPolicy: .limitedTextSummary,
            privacyPolicyRef: "privacy-v1"
        )
        let bridge =
            AICategorySuggestionSuggestionBridge(result: .success(.aiCategorySuggestionSuggested(fileID: file.id)))
        let suggestionModel = aiCategorySuggestionSuggestionModel(request: request, bridge: bridge)

        await model.selectFiles([file.id])
        model.beginAIClassificationSuggestion(fileID: file.id)
        await suggestionModel.askForSuggestion()
        model.beginAIClassificationChange(
            fileID: file.id,
            targetCategory: suggestionModel.suggestion?.suggestedCategory
        )
        let recordedRequests = await bridge.recordedRequests()

        XCTAssertEqual(recordedRequests, [request])
        XCTAssertNil(suggestionModel.acceptDisabledReason)
        XCTAssertEqual(
            model.pendingActionDestination,
            .changeCategory(fileID: file.id, initialTargetCategory: "finance/invoices", mode: .classifierCorrection)
        )
        XCTAssertEqual(model.files, [file])
        XCTAssertEqual(model.changeCategoryState, .idle)
    }

    @MainActor
    func testAICategorySuggestionPrivacyRuleReferenceLoadsMatchedAIPrivacyRulesCoreRule() async throws {
        let bridge = RemotePrivacyRulesBridge()
        let model = aiCategorySuggestionPrivacyRuleReferenceModel(ruleID: "rule-confidential", bridge: bridge)

        await model.load()
        let reference = try XCTUnwrap(model.reference)
        let requests = await bridge.requests()

        XCTAssertEqual(requests.loadCount, 1)
        XCTAssertEqual(reference.ruleID, "rule-confidential")
        XCTAssertEqual(reference.name, "Block confidential")
        XCTAssertEqual(reference.kind, .keyword)
        XCTAssertEqual(reference.pattern, "confidential")
        XCTAssertEqual(reference.appliesTo, .remoteAi)
        XCTAssertEqual(reference.matchCount, 4)
    }

    @MainActor
    func testAICategorySuggestionPrivacyRuleReferenceReportsMissingAIPrivacyRulesCoreRule() async {
        let model = aiCategorySuggestionPrivacyRuleReferenceModel(
            ruleID: "missing-rule",
            bridge: RemotePrivacyRulesBridge()
        )

        await model.load()

        XCTAssertEqual(model.state, .notFound("missing-rule"))
    }

    @MainActor
    func testAICategorySuggestionPrivacyRuleReferenceMapsAIPrivacyRulesCoreLoadError() async {
        let model = aiCategorySuggestionPrivacyRuleReferenceModel(
            ruleID: "rule-confidential",
            bridge: AIPrivacyRulesFailingBridge()
        )

        await model.load()

        guard case let .failed(error) = model.state else {
            XCTFail("Expected privacy rule load failure.")
            return
        }
        XCTAssertEqual(error.message, "AI privacy rule could not be loaded.")
        XCTAssertEqual(error.recovery, "Open privacy rules")
        XCTAssertEqual(error.detail, "Mapped ai-privacy-rules-core core error")
    }

    @MainActor
    func testAICategorySuggestionCoreErrorUsesSharedErrorMapper() async {
        let request = AIClassificationSuggestionRequestState(fileID: 406, contextPolicy: .fileNameOnly)
        let model = aiCategorySuggestionSuggestionModel(
            request: request,
            bridge: AICategorySuggestionSuggestionBridge(result: .failure(CoreError
                    .Config(reason: "AI settings disabled"))),
            fallbackBridge: AICategorySuggestionFallbackBridge(status: .aiCategorySuggestionInternalFailure())
        )

        await model.askForSuggestion()

        XCTAssertEqual(model.statusText, "AI suggestion failed.")
        XCTAssertEqual(model.failure?.message, "AI category suggestion could not be loaded.")
        XCTAssertEqual(model.failure?.recovery, "Open AI settings")
        XCTAssertEqual(model.failure?.detail, "Mapped ai-classification-suggestion core error")
        XCTAssertEqual(model.acceptDisabledReason, "No suggestion to accept.")
        XCTAssertEqual(model.fallbackStatus?.nonAiFallbackAction, .classifyManually)
    }
}
