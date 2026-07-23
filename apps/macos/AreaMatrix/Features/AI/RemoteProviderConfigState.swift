import Combine
import Foundation

enum RemoteProviderKindState: String, CaseIterable, Equatable, Identifiable {
    case openAi, anthropic, other

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .openAi: L10n.string("OpenAI")
        case .anthropic: L10n.string("Anthropic")
        case .other: L10n.string("Other")
        }
    }
}

enum RemoteProviderTestStatusState: String, Equatable {
    case succeeded, providerRejected, connectionFailed, unsupportedProvider
}

struct RemoteProviderTestRequestState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var keyReference: String
}

struct RemoteProviderEnableRequestState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var keyReference: String
    var featureScope: [AISettingsFeatureKind]
    var verificationToken: String
    var dataFlowConfirmed: Bool
}

struct RemoteProviderDisableRequestState: Equatable {
    var removeStoredCredential: Bool
}

struct RemoteProviderConfigState: Equatable {
    var providerConfigured: Bool
    var providerVerified: Bool
    var remoteProviderEnabled: Bool
    var provider: RemoteProviderKindState?
    var modelID: String?
    var endpointURL: String?
    var credentialConfigured: Bool
    var featureScope: [AISettingsFeatureKind]
    var updatedAt: Int64?
    var disabledReason: String?
}

struct RemoteProviderTestResultState: Equatable {
    var provider: RemoteProviderKindState
    var modelID: String
    var endpointURL: String?
    var status: RemoteProviderTestStatusState
    var providerVerified: Bool
    var verificationToken: String?
    var sanitizedMessage: String
}

enum RemotePrivacyGateAction: Equatable {
    case enable, disable
}

@MainActor
final class RemotePrivacyGateModel: ObservableObject {
    @Published private(set) var snapshot: AiPrivacyRulesSnapshot?
    @Published private(set) var failure: AISettingsError?
    @Published private(set) var pendingAction: RemotePrivacyGateAction?
    @Published private(set) var isSaving = false

    let repoPath: String
    private let bridge: any CoreAIPrivacyRulesManaging
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        bridge: any CoreAIPrivacyRulesManaging = CoreBridge(),
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper
    ) {
        self.repoPath = repoPath
        self.bridge = bridge
        self.errorMapper = errorMapper
    }

    var statusText: String {
        if isSaving { return L10n.string("Updating privacy gate...") }
        guard let snapshot else { return L10n.string("Privacy rules are loading.") }
        if snapshot.privacyGateEnabled {
            return L10n.string("Privacy gate is on. Rules are checked before every remote AI call.")
        }
        return L10n.string("Privacy gate is off. Remote AI calls are blocked until the gate is enabled.")
    }

    func load() async {
        guard !isSaving else { return }
        do {
            snapshot = try await bridge.loadAIPrivacyRules(repoPath: repoPath)
            failure = nil
        } catch {
            failure = await privacyError(
                for: error,
                message: L10n.message("Remote privacy rules could not be loaded."),
                recovery: L10n.message("Retry loading privacy rules before enabling remote AI.")
            )
        }
    }

    @discardableResult
    func enablePrivacyGate(providerConfig: RemoteProviderConfigState?) async -> Bool {
        await setPrivacyGate(
            true,
            action: .enable,
            providerConfig: providerConfig,
            message: L10n.message("Remote provider was configured, but privacy gate could not be enabled."),
            recovery: L10n.message("Retry enable privacy gate, open privacy rules, or disable remote AI.")
        )
    }

    @discardableResult
    func disablePrivacyGate(providerConfig: RemoteProviderConfigState?) async -> Bool {
        await setPrivacyGate(
            false,
            action: .disable,
            providerConfig: providerConfig,
            message: L10n.message("Remote AI was disabled, but privacy gate could not be disabled."),
            recovery: L10n.message("Retry disable privacy gate. Remote provider remains disabled.")
        )
    }

    @discardableResult
    func retryPending(providerConfig: RemoteProviderConfigState?) async -> Bool {
        switch pendingAction {
        case .enable:
            await enablePrivacyGate(providerConfig: providerConfig)
        case .disable:
            await disablePrivacyGate(providerConfig: providerConfig)
        case nil:
            false
        }
    }

    private func setPrivacyGate(
        _ enabled: Bool,
        action: RemotePrivacyGateAction,
        providerConfig: RemoteProviderConfigState?,
        message: LocalizedMessage,
        recovery: LocalizedMessage
    ) async -> Bool {
        guard let providerConfig else {
            failure = AISettingsError(
                message: message,
                recovery: recovery,
                detail: L10n.string("Remote provider state is missing.")
            )
            pendingAction = action
            return false
        }

        isSaving = true
        defer { isSaving = false }
        do {
            let base = try await currentSnapshot()
            let updated = try await bridge.updateAIPrivacyRules(
                repoPath: repoPath,
                request: base.privacyGateUpdateRequest(enabled: enabled, providerConfig: providerConfig)
            )
            return handleUpdatedSnapshot(
                updated,
                expectedGate: enabled,
                action: action,
                message: message,
                recovery: recovery
            )
        } catch {
            failure = await privacyError(for: error, message: message, recovery: recovery)
            pendingAction = action
            return false
        }
    }

    private func currentSnapshot() async throws -> AiPrivacyRulesSnapshot {
        if let snapshot { return snapshot }
        let loaded = try await bridge.loadAIPrivacyRules(repoPath: repoPath)
        snapshot = loaded
        return loaded
    }

    private func handleUpdatedSnapshot(
        _ updated: AiPrivacyRulesSnapshot,
        expectedGate: Bool,
        action: RemotePrivacyGateAction,
        message: LocalizedMessage,
        recovery: LocalizedMessage
    ) -> Bool {
        snapshot = updated
        guard updated.privacyGateEnabled == expectedGate else {
            failure = AISettingsError(
                message: message,
                recovery: recovery,
                detail: L10n.string("Privacy gate returned unchanged.")
            )
            pendingAction = action
            return false
        }
        failure = nil
        pendingAction = nil
        return true
    }

    private func privacyError(
        for error: Error,
        message: LocalizedMessage,
        recovery: LocalizedMessage
    ) async -> AISettingsError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return AISettingsError(
                message: message,
                recovery: mapping.recoveryMessage(fallback: recovery),
                detail: mapping.userMessage
            )
        }
        return AISettingsError(message: message, recovery: recovery, detail: error.localizedDescription)
    }
}

private extension AiPrivacyRulesSnapshot {
    func privacyGateUpdateRequest(
        enabled: Bool,
        providerConfig: RemoteProviderConfigState
    ) -> AiPrivacyRulesUpdateRequest {
        AiPrivacyRulesUpdateRequest(
            privacyGateEnabled: enabled,
            rules: rules.map(AiPrivacyRuleInput.init(record:)),
            remoteAllowedFields: remoteAllowedFields.map(AiPrivacyFieldRule.init(fieldState:)),
            providerScope: AiPrivacyProviderScopeSnapshot(providerConfig: providerConfig),
            confirmed: true
        )
    }
}

private extension AiPrivacyRuleInput {
    init(record: AiPrivacyRuleRecord) {
        self.init(
            ruleId: record.ruleId,
            name: record.name,
            kind: record.kind,
            pattern: record.pattern,
            appliesTo: record.appliesTo,
            enabled: record.enabled,
            description: record.description
        )
    }
}

private extension AiPrivacyFieldRule {
    init(fieldState: AiPrivacyFieldState) {
        self.init(field: fieldState.field, allowRemote: fieldState.allowRemote)
    }
}

private extension AiPrivacyProviderScopeSnapshot {
    init(providerConfig: RemoteProviderConfigState) {
        self.init(
            providerConfigured: providerConfig.providerConfigured,
            providerVerified: providerConfig.providerVerified,
            remoteProviderEnabled: providerConfig.remoteProviderEnabled,
            featureScope: providerConfig.featureScope.map(AiFeatureKind.init(snapshotFeature:))
        )
    }
}
