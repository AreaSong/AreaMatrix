@testable import AreaMatrix
import XCTest

extension RemoteProviderOutcome {
    var errorMessage: String? {
        switch self {
        case let .failed(error): error.message
        case .success: nil
        }
    }
}

@MainActor
func assertS303EnabledPageIntegration(
    remoteModel: RemoteProviderConfigModel,
    privacyModel: RemotePrivacyGateModel,
    providerRequests: RemoteProviderConfigBridge.Requests,
    privacyRequests: RemotePrivacyRulesBridge.Requests,
    store: RemoteProviderTestCredentialStore,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let expectedScopes: [AISettingsFeatureKind] = [.classificationSuggestions, .autoSummaries]
    let expectedCoreScopes = expectedScopes.map(AiFeatureKind.init(snapshotFeature:))
    XCTAssertEqual(providerRequests.loadCount, 1, file: file, line: line)
    XCTAssertEqual(providerRequests.test?.keyReference, "keychain:openAi-managed", file: file, line: line)
    XCTAssertEqual(providerRequests.enable?.featureScope, expectedScopes, file: file, line: line)
    XCTAssertEqual(providerRequests.enable?.dataFlowConfirmed, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.providerConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.providerVerified, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.remoteProviderEnabled, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.credentialConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.featureScope, expectedScopes, file: file, line: line)
    XCTAssertEqual(privacyModel.snapshot?.privacyGateEnabled, true, file: file, line: line)
    XCTAssertEqual(privacyRequests.updates.first?.privacyGateEnabled, true, file: file, line: line)
    XCTAssertEqual(privacyRequests.updates.first?.providerScope.remoteProviderEnabled, true, file: file, line: line)
    XCTAssertEqual(
        privacyRequests.updates.first?.providerScope.featureScope,
        expectedCoreScopes,
        file: file,
        line: line
    )
    XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "integration-api-key"], file: file, line: line)
}

@MainActor
func assertS303DisabledPageIntegration(
    remoteModel: RemoteProviderConfigModel,
    privacyModel: RemotePrivacyGateModel,
    providerRequests: RemoteProviderConfigBridge.Requests,
    privacyRequests: RemotePrivacyRulesBridge.Requests,
    store: RemoteProviderTestCredentialStore,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let expectedScopes: [AISettingsFeatureKind] = [.classificationSuggestions, .autoSummaries]
    XCTAssertEqual(providerRequests.disable?.removeStoredCredential, false, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.remoteProviderEnabled, false, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.credentialConfigured, true, file: file, line: line)
    XCTAssertEqual(remoteModel.snapshot?.featureScope, expectedScopes, file: file, line: line)
    XCTAssertEqual(privacyModel.snapshot?.privacyGateEnabled, false, file: file, line: line)
    XCTAssertEqual(privacyRequests.updates.last?.privacyGateEnabled, false, file: file, line: line)
    XCTAssertEqual(privacyRequests.updates.last?.providerScope.remoteProviderEnabled, false, file: file, line: line)
    XCTAssertEqual(store.storedKeys(), ["keychain:openAi-managed": "integration-api-key"], file: file, line: line)
    XCTAssertEqual(store.removedReferences(), [], file: file, line: line)
}

actor RemoteProviderConfigBridge: CoreRemoteProviderConfiguring {
    enum TestMode {
        case success, rejected, coreFailure
    }

    struct Requests: Equatable {
        var loadCount = 0
        var test: RemoteProviderTestRequestState?
        var enable: RemoteProviderEnableRequestState?
        var disable: RemoteProviderDisableRequestState?
    }

    private var initial: RemoteProviderConfigState
    private let testMode: TestMode
    private let enableFails: Bool
    private var recorded = Requests()

    init(
        initial: RemoteProviderConfigState = .remoteProviderConfigDisabled(),
        testMode: TestMode = .success,
        enableFails: Bool = false
    ) {
        self.initial = initial
        self.testMode = testMode
        self.enableFails = enableFails
    }

    func loadRemoteProviderConfig(repoPath _: String) async throws -> RemoteProviderConfigState {
        recorded.loadCount += 1
        return initial
    }

    func testRemoteProvider(repoPath _: String,
                            request: RemoteProviderTestRequestState) async throws -> RemoteProviderTestResultState {
        recorded.test = request
        switch testMode {
        case .coreFailure:
            throw CoreError.PermissionDenied(path: "remote provider credential")
        case .rejected:
            return RemoteProviderTestResultState(
                provider: request.provider,
                modelID: request.modelID,
                endpointURL: request.endpointURL,
                status: .providerRejected,
                providerVerified: false,
                verificationToken: nil,
                sanitizedMessage: "The API key was rejected by the provider."
            )
        case .success:
            break
        }

        return RemoteProviderTestResultState(
            provider: request.provider,
            modelID: request.modelID,
            endpointURL: request.endpointURL,
            status: .succeeded,
            providerVerified: true,
            verificationToken: "verified-s303",
            sanitizedMessage: "Connection verified"
        )
    }

    func enableRemoteProvider(repoPath _: String,
                              request: RemoteProviderEnableRequestState) async throws -> RemoteProviderConfigState {
        recorded.enable = request
        if enableFails {
            throw CoreError.Internal(message: "remote provider save failed")
        }
        let snapshot = RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: request.provider,
            modelID: request.modelID,
            endpointURL: request.endpointURL,
            credentialConfigured: true,
            featureScope: request.featureScope,
            updatedAt: 303,
            disabledReason: nil
        )
        initial = snapshot
        return snapshot
    }

    func disableRemoteProvider(repoPath _: String,
                               request: RemoteProviderDisableRequestState) async throws -> RemoteProviderConfigState {
        recorded.disable = request
        let snapshot = RemoteProviderConfigState(
            providerConfigured: !request.removeStoredCredential,
            providerVerified: !request.removeStoredCredential,
            remoteProviderEnabled: false,
            provider: request.removeStoredCredential ? nil : initial.provider,
            modelID: request.removeStoredCredential ? nil : initial.modelID,
            endpointURL: request.removeStoredCredential ? nil : initial.endpointURL,
            credentialConfigured: !request.removeStoredCredential,
            featureScope: request.removeStoredCredential ? [] : initial.featureScope,
            updatedAt: 304,
            disabledReason: "Remote AI disabled"
        )
        initial = snapshot
        return snapshot
    }

    func requests() -> Requests {
        recorded
    }
}

actor RemotePrivacyRulesBridge: CoreAIPrivacyRulesManaging, CoreAIPrivacyEvaluating {
    struct Requests: Equatable {
        var loadCount = 0
        var updates: [AiPrivacyRulesUpdateRequest] = []
        var evaluations: [AiPrivacyEvaluationRequest] = []
    }

    private var snapshot: AiPrivacyRulesSnapshot
    private let evaluationReport: AiPrivacyEvaluationReport
    private let updateFails: Bool
    private var recorded = Requests()

    init(
        snapshot: AiPrivacyRulesSnapshot = .s303PrivacyRules(),
        evaluationReport: AiPrivacyEvaluationReport = .s303AllowedPrivacyEvaluation(),
        updateFails: Bool = false
    ) {
        self.snapshot = snapshot
        self.evaluationReport = evaluationReport
        self.updateFails = updateFails
    }

    func loadAIPrivacyRules(repoPath _: String) async throws -> AiPrivacyRulesSnapshot {
        recorded.loadCount += 1
        return snapshot
    }

    func updateAIPrivacyRules(
        repoPath _: String,
        request: AiPrivacyRulesUpdateRequest
    ) async throws -> AiPrivacyRulesSnapshot {
        recorded.updates.append(request)
        if updateFails {
            throw CoreError.Db(message: "privacy gate write failed")
        }
        snapshot = snapshot.applyingPrivacyGateRequest(request)
        return snapshot
    }

    func evaluateAIPrivacy(
        repoPath _: String,
        request: AiPrivacyEvaluationRequest
    ) async throws -> AiPrivacyEvaluationReport {
        recorded.evaluations.append(request)
        return evaluationReport
    }

    func requests() -> Requests {
        recorded
    }
}

extension AiPrivacyEvaluationReport {
    static func s303AllowedPrivacyEvaluation() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .allowed,
            skippedReason: nil,
            providerGateReason: nil,
            matchedRules: [],
            matchedFieldType: nil,
            allowedFields: [.fileName, .repoRelativePath, .extension],
            blockedFields: [],
            sentFields: [.fileName, .repoRelativePath],
            message: "Privacy rules allow this AI request."
        )
    }

    static func s307PrivacyRuleBlocked() -> AiPrivacyEvaluationReport {
        AiPrivacyEvaluationReport(
            decision: .skipped,
            skippedReason: .privacyRule,
            providerGateReason: nil,
            matchedRules: [
                AiPrivacyRuleMatch(
                    ruleId: "rule-confidential",
                    name: "Block confidential",
                    kind: .keyword,
                    pattern: "confidential",
                    appliesTo: .remoteAi,
                    matchedField: .fileName
                )
            ],
            matchedFieldType: .fileName,
            allowedFields: [],
            blockedFields: [.fileName, .repoRelativePath, .extractedTextExcerpt],
            sentFields: [],
            message: "A privacy rule blocked the tag suggestion input."
        )
    }
}

extension RemoteProviderConfigState {
    static func remoteProviderConfigDisabled() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: false,
            providerVerified: false,
            remoteProviderEnabled: false,
            provider: nil,
            modelID: nil,
            endpointURL: nil,
            credentialConfigured: false,
            featureScope: [],
            updatedAt: nil,
            disabledReason: "Remote AI is off"
        )
    }

    static func remoteProviderConfigEnabled() -> RemoteProviderConfigState {
        RemoteProviderConfigState(
            providerConfigured: true,
            providerVerified: true,
            remoteProviderEnabled: true,
            provider: .openAi,
            modelID: "gpt-4.1-mini",
            endpointURL: nil,
            credentialConfigured: true,
            featureScope: [.autoSummaries],
            updatedAt: 302,
            disabledReason: nil
        )
    }
}

extension AiPrivacyRulesSnapshot {
    static func s303PrivacyRules(
        privacyGateEnabled: Bool = false,
        featureScope: [AiFeatureKind] = [.autoSummaries]
    ) -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: privacyGateEnabled,
            rules: [.s303RuleRecord()],
            remoteAllowedFields: [
                AiPrivacyFieldState(field: .fileName, allowRemote: true, lastMatchedCount: 0),
                AiPrivacyFieldState(field: .extractedTextExcerpt, allowRemote: false, lastMatchedCount: 2),
                AiPrivacyFieldState(field: .noteSummary, allowRemote: true, lastMatchedCount: 0)
            ],
            providerScope: AiPrivacyProviderScopeSnapshot(
                providerConfigured: true,
                providerVerified: true,
                remoteProviderEnabled: false,
                featureScope: featureScope
            ),
            updatedAt: 901,
            remoteBlockedByDefault: true
        )
    }

    func applyingPrivacyGateRequest(_ request: AiPrivacyRulesUpdateRequest) -> AiPrivacyRulesSnapshot {
        AiPrivacyRulesSnapshot(
            privacyGateEnabled: request.privacyGateEnabled,
            rules: request.rules.map(AiPrivacyRuleRecord.init(input:)),
            remoteAllowedFields: request.remoteAllowedFields.map(AiPrivacyFieldState.init(rule:)),
            providerScope: request.providerScope,
            updatedAt: 902,
            remoteBlockedByDefault: remoteBlockedByDefault
        )
    }
}

extension AiPrivacyRuleRecord {
    static func s303RuleRecord() -> AiPrivacyRuleRecord {
        AiPrivacyRuleRecord(
            ruleId: "rule-confidential",
            name: "Block confidential",
            kind: .keyword,
            pattern: "confidential",
            appliesTo: .remoteAi,
            enabled: true,
            description: "Fixture privacy rule",
            matchCount: 4,
            lastMatchedAt: 900
        )
    }

    init(input: AiPrivacyRuleInput) {
        self.init(
            ruleId: input.ruleId ?? "generated-rule",
            name: input.name,
            kind: input.kind,
            pattern: input.pattern,
            appliesTo: input.appliesTo,
            enabled: input.enabled,
            description: input.description,
            matchCount: 0,
            lastMatchedAt: nil
        )
    }
}

extension AiPrivacyFieldState {
    init(rule: AiPrivacyFieldRule) {
        self.init(field: rule.field, allowRemote: rule.allowRemote, lastMatchedCount: 0)
    }
}

@MainActor
final class RemoteProviderTestCredentialStore: RemoteProviderCredentialStoring {
    enum FailureMode {
        case never, oneShot, always

        mutating func shouldFail() -> Bool {
            switch self {
            case .never:
                return false
            case .oneShot:
                self = .never
                return true
            case .always:
                return true
            }
        }
    }

    private var keys: [String: String] = [:]
    private var removed: [String] = []
    private var rollbacks: [UUID: RemoteProviderConfigCredentialRollback] = [:]
    private var discardFailure: FailureMode
    private var removeFailure: FailureMode

    init(discardFailure: FailureMode = .never, removeFailure: FailureMode = .never) {
        self.discardFailure = discardFailure
        self.removeFailure = removeFailure
    }

    func storeCredential(
        provider: RemoteProviderKindState,
        endpointURL: String?,
        apiKey: String
    ) throws -> RemoteProviderCredentialDraft {
        let reference = storedCredentialReference(provider: provider, endpointURL: endpointURL)
        let draft = RemoteProviderCredentialDraft(
            reference: reference,
            replacesExistingCredential: keys[reference] != nil
        )
        rollbacks[draft.id] = keys[reference]
            .map { .existing(reference: reference, value: $0) } ?? .missing(reference: reference)
        keys[reference] = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft
    }

    func discardCredentialDraft(_ draft: RemoteProviderCredentialDraft) throws {
        if discardFailure.shouldFail() {
            throw RemoteProviderConfigCredentialStoreError.cleanupFailed
        }
        guard let rollback = rollbacks[draft.id] else { return }
        switch rollback {
        case let .existing(_, previous):
            keys[draft.reference] = previous
        case .missing:
            keys.removeValue(forKey: draft.reference)
            removed.append(draft.reference)
        }
        rollbacks.removeValue(forKey: draft.id)
    }

    func commitCredentialDraft(_ draft: RemoteProviderCredentialDraft) {
        rollbacks.removeValue(forKey: draft.id)
    }

    func removeCredential(reference: String) throws {
        if removeFailure.shouldFail() {
            throw RemoteProviderConfigCredentialStoreError.cleanupFailed
        }
        rollbacks = rollbacks.filter { $0.value.reference != reference }
        removed.append(reference)
        keys.removeValue(forKey: reference)
    }

    func storedCredentialReference(provider: RemoteProviderKindState, endpointURL: String?) -> String {
        let suffix = endpointURL?.isEmpty == false ? endpointURL ?? "managed" : "managed"
        return "keychain:\(provider.rawValue)-\(suffix)"
    }

    func storedKeys() -> [String: String] {
        keys
    }

    func removedReferences() -> [String] {
        removed
    }

    func seedCredential(provider: RemoteProviderKindState = .openAi, endpointURL: String? = nil,
                        apiKey: String) -> String {
        let reference = storedCredentialReference(provider: provider, endpointURL: endpointURL)
        keys[reference] = apiKey
        return reference
    }
}

private enum RemoteProviderConfigCredentialRollback {
    case missing(reference: String)
    case existing(reference: String, value: String)

    var reference: String {
        switch self {
        case let .missing(reference), let .existing(reference, _):
            reference
        }
    }
}

private enum RemoteProviderConfigCredentialStoreError: LocalizedError {
    case cleanupFailed

    var errorDescription: String? {
        "Keychain cleanup failed."
    }
}

actor RemoteProviderConfigErrorMapper: CoreErrorMapping {
    func mapCoreError(_: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .internal,
            userMessage: "Remote provider save failed",
            severity: .medium,
            suggestedAction: "Retry",
            recoverability: .retryable,
            rawContext: "S3-03 remote provider"
        )
    }
}
