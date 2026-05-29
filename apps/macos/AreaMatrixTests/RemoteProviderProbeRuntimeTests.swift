@testable import AreaMatrix
import Foundation
import XCTest

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

        let repoURL = try makeTemporaryRepoURL()
        defer { try? FileManager.default.removeItem(at: repoURL) }
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
    func testS304AskSuggestionUsesC304BridgeAndKeepsDraftPending() async {
        let request = AIClassificationSuggestionRequestState(
            fileID: 404,
            contextPolicy: .limitedTextSummary,
            privacyPolicyRef: "privacy-v1"
        )
        let bridge = S304SuggestionBridge(result: .success(.s304Suggested(fileID: request.fileID)))
        let model = s304SuggestionModel(request: request, bridge: bridge)

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
    func testS304PrivacySkipMapsToDisabledAcceptState() async {
        let request = AIClassificationSuggestionRequestState(fileID: 405, contextPolicy: .fileNameAndPath)
        let bridge = S304SuggestionBridge(result: .success(.s304PrivacySkipped(fileID: request.fileID)))
        let fallbackBridge = S304FallbackBridge(status: .s304PrivacySkipped(callLogID: 305))
        let model = s304SuggestionModel(request: request, bridge: bridge, fallbackBridge: fallbackBridge)

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
    func testS304PrivacySkippedPanelOffersC309PrivacyRuleReferenceAction() async {
        let request = AIClassificationSuggestionRequestState(fileID: 407, contextPolicy: .fileNameAndPath)
        let bridge = S304SuggestionBridge(result: .success(.s304PrivacySkipped(fileID: request.fileID)))
        let fallbackBridge = S304FallbackBridge(status: .s304PrivacySkipped(callLogID: 305))
        let model = s304SuggestionModel(request: request, bridge: bridge, fallbackBridge: fallbackBridge)

        await model.askForSuggestion()
        let panel = AIClassificationSuggestionPanel(
            model: model,
            fileName: "confidential.pdf",
            currentPath: "inbox/confidential.pdf"
        )
        let body = s135MirrorDescription(of: panel.body)

        XCTAssertTrue(body.contains("View privacy rule"))
        XCTAssertTrue(body.contains("Classify manually"))
        XCTAssertFalse(panel.isFallbackActionDisabled(.viewPrivacyRule))
    }

    @MainActor
    func testS304ProviderUnavailableUsesC310RetryableFallbackStatus() async {
        let request = AIClassificationSuggestionRequestState(fileID: 408, contextPolicy: .fileNameOnly)
        let fallbackBridge = S304FallbackBridge(status: .s304ProviderUnavailable(callLogID: 306))
        let model = s304SuggestionModel(
            request: request,
            bridge: S304SuggestionBridge(result: .success(.s304ProviderUnavailable(fileID: request.fileID))),
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
    func testS304StandardC310RecoveryActionsAreVisibleAndTriggerable() {
        let model = s304SuggestionModel(
            request: AIClassificationSuggestionRequestState(fileID: 409, contextPolicy: .fileNameOnly),
            bridge: S304SuggestionBridge(result: .success(.s304ProviderUnavailable(fileID: 409)))
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
    func testS304C310ViewCallLogActionUsesFallbackCallLogID() async {
        let fallbackBridge = S304FallbackBridge(status: .s304ProviderUnavailable(callLogID: 730))
        let model = s304SuggestionModel(
            request: AIClassificationSuggestionRequestState(fileID: 409, contextPolicy: .fileNameOnly),
            bridge: S304SuggestionBridge(result: .success(.s304ProviderUnavailable(fileID: 409))),
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
    func testS304PageIntegrationKeepsSuggestionDraftUntilClassifierExit() async {
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
        let bridge = S304SuggestionBridge(result: .success(.s304Suggested(fileID: file.id)))
        let suggestionModel = s304SuggestionModel(request: request, bridge: bridge)

        await model.selectFiles([file.id])
        model.beginAIClassificationSuggestion(fileID: file.id)
        await suggestionModel.askForSuggestion()
        model.beginAIClassificationChange(fileID: file.id, targetCategory: suggestionModel.suggestion?.suggestedCategory)
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
    func testS304PrivacyRuleReferenceLoadsMatchedC309Rule() async throws {
        let bridge = RemotePrivacyRulesBridge()
        let model = s304PrivacyRuleReferenceModel(ruleID: "rule-confidential", bridge: bridge)

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
    func testS304PrivacyRuleReferenceReportsMissingC309Rule() async {
        let model = s304PrivacyRuleReferenceModel(ruleID: "missing-rule", bridge: RemotePrivacyRulesBridge())

        await model.load()

        XCTAssertEqual(model.state, .notFound("missing-rule"))
    }

    @MainActor
    func testS304PrivacyRuleReferenceMapsC309LoadError() async {
        let model = s304PrivacyRuleReferenceModel(ruleID: "rule-confidential", bridge: S304PrivacyRulesFailingBridge())

        await model.load()

        guard case let .failed(error) = model.state else {
            XCTFail("Expected privacy rule load failure.")
            return
        }
        XCTAssertEqual(error.message, "AI privacy rule could not be loaded.")
        XCTAssertEqual(error.recovery, "Open privacy rules")
        XCTAssertEqual(error.detail, "Mapped C3-09 core error")
    }

    @MainActor
    func testS304CoreErrorUsesSharedErrorMapper() async {
        let request = AIClassificationSuggestionRequestState(fileID: 406, contextPolicy: .fileNameOnly)
        let model = s304SuggestionModel(
            request: request,
            bridge: S304SuggestionBridge(result: .failure(CoreError.Config(reason: "AI settings disabled"))),
            fallbackBridge: S304FallbackBridge(status: .s304InternalFailure())
        )

        await model.askForSuggestion()

        XCTAssertEqual(model.statusText, "AI suggestion failed.")
        XCTAssertEqual(model.failure?.message, "AI category suggestion could not be loaded.")
        XCTAssertEqual(model.failure?.recovery, "Open AI settings")
        XCTAssertEqual(model.failure?.detail, "Mapped C3-04 core error")
        XCTAssertEqual(model.acceptDisabledReason, "No suggestion to accept.")
        XCTAssertEqual(model.fallbackStatus?.nonAiFallbackAction, .classifyManually)
    }
}

private func makeTemporaryRepoURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixRemoteProviderProbeRuntimeTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
private func s304PrivacyRuleReferenceModel(
    ruleID: String,
    bridge: any CoreAIPrivacyRulesManaging
) -> AIClassificationPrivacyRuleReferenceModel {
    AIClassificationPrivacyRuleReferenceModel(
        repoPath: "/tmp/repo",
        ruleID: ruleID,
        bridge: bridge,
        errorMapper: S304PrivacyRuleErrorMapper()
    )
}

private final class ProbeRuntimeRecorder {
    let endpointURL = "http://127.0.0.1:1/probe"
    let evidenceURL: URL
    let runtimeURL: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AreaMatrixRemoteProviderProbeRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        evidenceURL = directory.appendingPathComponent("probe-runtime-evidence.txt")
        runtimeURL = directory.appendingPathComponent("probe-runtime-recorder.sh")
        try recorderScript.write(to: runtimeURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: runtimeURL.path)
    }

    func evidence() throws -> String {
        try String(contentsOf: evidenceURL, encoding: .utf8)
    }

    private var recorderScript: String {
        #"""
        #!/bin/sh
        set -eu
        payload="$(mktemp "${TMPDIR:-/tmp}/areamatrix-remote-provider-probe-test.XXXXXX")"
        trap 'rm -f "$payload"' EXIT
        cat > "$payload"
        provider="$(/usr/bin/plutil -extract provider raw -o - "$payload")"
        url="$(/usr/bin/plutil -extract url raw -o - "$payload")"
        key_reference="$(/usr/bin/plutil -extract key_reference raw -o - "$payload")"
        if [ "${key_reference#keychain:}" != "$key_reference" ]; then
            credential_reference_shape='keychain'
            status='Succeeded'
        else
            credential_reference_shape='unsupported'
            status='ConnectionFailed'
        fi
        {
            printf 'provider=%s\n' "$provider"
            printf 'url=%s\n' "$url"
            printf 'key_reference=%s\n' "$key_reference"
            printf 'credential_reference_shape=%s\n' "$credential_reference_shape"
        } > "$AREAMATRIX_REMOTE_PROVIDER_PROBE_EVIDENCE"
        printf '%s\n' "$status"
        """#
    }
}

private final class ProbeRuntimeEnvironment {
    private let oldRuntime: String?
    private let oldEvidence: String?
    private let runtimePath: String?
    private let evidencePath: String?

    init(runtimePath: String?, evidencePath: String?) {
        oldRuntime = environmentString(RemoteProviderProbeRuntimeInstaller.environmentKey)
        oldEvidence = environmentString("AREAMATRIX_REMOTE_PROVIDER_PROBE_EVIDENCE")
        self.runtimePath = runtimePath
        self.evidencePath = evidencePath
    }

    func install() {
        setEnvironmentValue(runtimePath, for: RemoteProviderProbeRuntimeInstaller.environmentKey)
        setEnvironmentValue(evidencePath, for: "AREAMATRIX_REMOTE_PROVIDER_PROBE_EVIDENCE")
    }

    func clearRuntime() {
        unsetenv(RemoteProviderProbeRuntimeInstaller.environmentKey)
    }

    func restore() {
        setEnvironmentValue(oldRuntime, for: RemoteProviderProbeRuntimeInstaller.environmentKey)
        setEnvironmentValue(oldEvidence, for: "AREAMATRIX_REMOTE_PROVIDER_PROBE_EVIDENCE")
    }

    private func setEnvironmentValue(_ value: String?, for key: String) {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
}

private func environmentString(_ key: String) -> String? {
    guard let pointer = getenv(key) else { return nil }
    return String(cString: pointer)
}

private actor S304PrivacyRulesFailingBridge: CoreAIPrivacyRulesManaging {
    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        throw CoreError.Db(message: "privacy rules read failed")
    }

    func updateAIPrivacyRules(
        repoPath _: String,
        request _: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot {
        throw CoreError.Db(message: "privacy rules write failed")
    }
}

private struct S304PrivacyRuleErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .db,
            userMessage: "Mapped C3-09 core error",
            severity: .medium,
            suggestedAction: "Open privacy rules",
            recoverability: .userActionRequired,
            rawContext: "S3-04 C3-09"
        )
    }
}

private extension AIClassificationSuggestionState {
    static func s304PrivacySkipped(fileID: Int64) -> AIClassificationSuggestionState {
        AIClassificationSuggestionState(
            fileID: fileID,
            status: .skipped,
            currentCategory: "inbox",
            suggestedCategory: nil,
            confidence: 0,
            reason: nil,
            route: nil,
            usedContext: [],
            skippedReason: .privacyRule,
            privacyRuleID: "rule-confidential",
            callLogID: 305,
            requiresUserConfirmation: true
        )
    }
}
