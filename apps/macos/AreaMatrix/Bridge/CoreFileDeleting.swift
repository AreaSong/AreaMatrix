import Foundation

protocol CoreFileDeleting: Sendable {
    func deleteFile(repoPath: String, fileID: Int64) async throws
    func removeIndexEntry(repoPath: String, fileID: Int64) async throws
}

protocol CoreAISettingsLoading: Sendable {
    func loadAISettings(repoPath: String) async throws -> AISettingsSnapshot
}

protocol CoreAISettingsUpdating: Sendable {
    func updateAISettings(repoPath: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot
}

enum AISettingsProviderPreference: String, CaseIterable, Equatable, Identifiable {
    case localFirst, localOnly, remoteFirst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .localFirst: "Local first"
        case .localOnly: "Local only"
        case .remoteFirst: "Remote first"
        }
    }
}

enum AISettingsFeatureKind: String, CaseIterable, Equatable, Identifiable {
    case classificationSuggestions, autoSummaries, autoTags, semanticSearch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classificationSuggestions: "Classification suggestions"
        case .autoSummaries: "Auto summaries"
        case .autoTags: "Auto tags"
        case .semanticSearch: "Semantic search"
        }
    }

    var providerLabel: String {
        switch self {
        case .classificationSuggestions: "Local preferred"
        case .autoSummaries, .autoTags: "Local or remote"
        case .semanticSearch: "Local index by default"
        }
    }
}

struct AISettingsFeatureConfigSnapshot: Equatable {
    var feature: AISettingsFeatureKind
    var enabled: Bool
    var allowRemote: Bool
}

struct AISettingsCapabilitySnapshot: Equatable, Identifiable {
    var feature: AISettingsFeatureKind
    var enabled: Bool
    var localAllowed: Bool
    var remoteAllowed: Bool
    var disabledReason: String?

    var id: String { feature.rawValue }
}

struct AISettingsConfigSnapshot: Equatable {
    var repoPath: String
    var aiEnabled: Bool
    var providerPreference: AISettingsProviderPreference
    var localAIEnabled: Bool
    var remoteAIAllowed: Bool
    var privacyGateEnabled: Bool
    var privacyPolicyRef: String?
    var featureToggles: [AISettingsFeatureConfigSnapshot]
}

struct AISettingsSnapshot: Equatable {
    var config: AISettingsConfigSnapshot
    var capabilities: [AISettingsCapabilitySnapshot]
    var updatedAt: Int64?

    init(config: AISettingsConfigSnapshot, capabilities: [AISettingsCapabilitySnapshot], updatedAt: Int64?) {
        self.config = config.normalized()
        self.capabilities = capabilities
        self.updatedAt = updatedAt
    }

    init(coreSnapshot: AiConfigSnapshot) {
        self.init(
            config: AISettingsConfigSnapshot(coreConfig: coreSnapshot.config),
            capabilities: coreSnapshot.capabilities.map(AISettingsCapabilitySnapshot.init(coreCapability:)),
            updatedAt: coreSnapshot.updatedAt
        )
    }

    func withPendingConfig(_ pendingConfig: AISettingsConfigSnapshot) -> AISettingsSnapshot {
        let normalized = pendingConfig.normalized()
        return AISettingsSnapshot(
            config: normalized,
            capabilities: AISettingsCapabilitySnapshot.derived(from: normalized),
            updatedAt: updatedAt
        )
    }
}

extension CoreBridge: CoreFileDeleting {
    func deleteFile(repoPath: String, fileID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try deleteCoreFile(repoPath: repoPath, fileID: fileID)
        }.value
    }

    func removeIndexEntry(repoPath: String, fileID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try removeCoreIndexEntry(repoPath: repoPath, fileID: fileID)
        }.value
    }
}

extension CoreBridge: CoreAISettingsLoading, CoreAISettingsUpdating {
    func loadAISettings(repoPath: String) async throws -> AISettingsSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AISettingsSnapshot(coreSnapshot: loadAiConfig(repoPath: repoPath))
        }.value
    }

    func updateAISettings(repoPath: String, newConfig: AISettingsConfigSnapshot) async throws -> AISettingsSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try AISettingsSnapshot(coreSnapshot: updateAiConfig(
                repoPath: repoPath,
                newConfig: AiConfig(snapshot: newConfig)
            ))
        }.value
    }
}

private func deleteCoreFile(repoPath: String, fileID: Int64) throws {
    try deleteFile(repoPath: repoPath, fileId: fileID)
}

private func removeCoreIndexEntry(repoPath: String, fileID: Int64) throws {
    try removeIndexEntry(repoPath: repoPath, fileId: fileID)
}

extension AISettingsConfigSnapshot {
    init(coreConfig: AiConfig) {
        repoPath = coreConfig.repoPath
        aiEnabled = coreConfig.aiEnabled
        providerPreference = AISettingsProviderPreference(corePreference: coreConfig.providerPreference)
        localAIEnabled = coreConfig.localAiEnabled
        remoteAIAllowed = coreConfig.remoteAiAllowed
        privacyGateEnabled = coreConfig.privacyGateEnabled
        privacyPolicyRef = coreConfig.privacyPolicyRef
        featureToggles = coreConfig.featureToggles.map(AISettingsFeatureConfigSnapshot.init(coreConfig:))
    }

    func normalized() -> AISettingsConfigSnapshot {
        var config = self
        config.featureToggles = AISettingsFeatureKind.allCases.map { feature in
            featureToggles.first { $0.feature == feature } ??
                AISettingsFeatureConfigSnapshot(feature: feature, enabled: false, allowRemote: false)
        }
        if !config.remoteAIAllowed && config.providerPreference == .remoteFirst {
            config.providerPreference = .localFirst
        }
        return config
    }

    mutating func setFeature(_ feature: AISettingsFeatureKind, enabled: Bool) {
        self = normalized()
        guard let index = featureToggles.firstIndex(where: { $0.feature == feature }) else { return }
        featureToggles[index].enabled = enabled
    }
}

extension AISettingsCapabilitySnapshot {
    init(coreCapability: AiCapabilityState) {
        feature = AISettingsFeatureKind(coreFeature: coreCapability.feature)
        enabled = coreCapability.enabled
        localAllowed = coreCapability.localAllowed
        remoteAllowed = coreCapability.remoteAllowed
        disabledReason = coreCapability.disabledReason
    }

    static func derived(from config: AISettingsConfigSnapshot) -> [AISettingsCapabilitySnapshot] {
        config.featureToggles.map { toggle in
            let enabled = config.aiEnabled && toggle.enabled
            let remoteEnabled = enabled && config.remoteAIAllowed && config.providerPreference != .localOnly &&
                toggle.allowRemote && config.privacyGateEnabled
            return AISettingsCapabilitySnapshot(
                feature: toggle.feature,
                enabled: enabled,
                localAllowed: enabled && config.localAIEnabled,
                remoteAllowed: remoteEnabled,
                disabledReason: disabledReason(config: config, toggle: toggle)
            )
        }
    }

    private static func disabledReason(
        config: AISettingsConfigSnapshot,
        toggle: AISettingsFeatureConfigSnapshot
    ) -> String? {
        if !config.aiEnabled { return "AI is off" }
        if !toggle.enabled { return "Feature is off" }
        if config.localAIEnabled { return nil }
        if config.remoteAIAllowed && toggle.allowRemote && config.privacyGateEnabled { return nil }
        return "No AI route is enabled"
    }
}

extension AISettingsFeatureConfigSnapshot {
    init(coreConfig: AiFeatureConfig) {
        feature = AISettingsFeatureKind(coreFeature: coreConfig.feature)
        enabled = coreConfig.enabled
        allowRemote = coreConfig.allowRemote
    }
}

extension AiConfig {
    init(snapshot: AISettingsConfigSnapshot) {
        let normalized = snapshot.normalized()
        self.init(
            repoPath: normalized.repoPath,
            aiEnabled: normalized.aiEnabled,
            providerPreference: AiProviderPreference(snapshotPreference: normalized.providerPreference),
            localAiEnabled: normalized.localAIEnabled,
            remoteAiAllowed: normalized.remoteAIAllowed,
            privacyGateEnabled: normalized.privacyGateEnabled,
            privacyPolicyRef: normalized.privacyPolicyRef,
            featureToggles: normalized.featureToggles.map(AiFeatureConfig.init(snapshot:))
        )
    }
}

extension AiFeatureConfig {
    init(snapshot: AISettingsFeatureConfigSnapshot) {
        self.init(
            feature: AiFeatureKind(snapshotFeature: snapshot.feature),
            enabled: snapshot.enabled,
            allowRemote: snapshot.allowRemote
        )
    }
}

private extension AISettingsProviderPreference {
    init(corePreference: AiProviderPreference) {
        switch corePreference {
        case .localOnly: self = .localOnly
        case .remoteFirst: self = .remoteFirst
        case .localFirst: self = .localFirst
        }
    }
}

extension AISettingsFeatureKind {
    init(coreFeature: AiFeatureKind) {
        switch coreFeature {
        case .classificationSuggestions: self = .classificationSuggestions
        case .autoSummaries: self = .autoSummaries
        case .autoTags: self = .autoTags
        case .semanticSearch: self = .semanticSearch
        }
    }
}

private extension AiProviderPreference {
    init(snapshotPreference: AISettingsProviderPreference) {
        switch snapshotPreference {
        case .localFirst: self = .localFirst
        case .localOnly: self = .localOnly
        case .remoteFirst: self = .remoteFirst
        }
    }
}

extension AiFeatureKind {
    init(snapshotFeature: AISettingsFeatureKind) {
        switch snapshotFeature {
        case .classificationSuggestions: self = .classificationSuggestions
        case .autoSummaries: self = .autoSummaries
        case .autoTags: self = .autoTags
        case .semanticSearch: self = .semanticSearch
        }
    }
}
