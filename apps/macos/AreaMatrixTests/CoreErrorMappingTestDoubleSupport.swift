@testable import AreaMatrix

actor StaticCoreErrorMapper: CoreErrorMapping {
    private let mapping: CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

actor RecordingCoreErrorMapper: CoreErrorMapping {
    private let mapping: @Sendable (CoreError) -> CoreErrorMappingSnapshot
    private var errors: [CoreError] = []

    init(mapping: @escaping @Sendable (CoreError) -> CoreErrorMappingSnapshot) {
        self.mapping = mapping
    }

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        return mapping(error)
    }

    func recordedErrors() -> [CoreError] {
        errors
    }
}

extension RecordingCoreErrorMapper {
    static func aiPrivacyRulesSettingsConfig() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot(
                kind: .io,
                userMessage: String(describing: error),
                severity: .medium,
                suggestedAction: "Retry save",
                recoverability: .retryable,
                rawContext: "ai-privacy-rules ai-settings-config"
            )
        }
    }

    static func batchChangeCategory() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot(
                kind: CoreErrorKindTestMapper.kind(for: error),
                userMessage: "Batch category update failed",
                severity: .medium,
                suggestedAction: "Review failed items and refresh the preview.",
                recoverability: .refreshRequired,
                rawContext: "batch-change-category batch-change-category-core batch-change-category"
            )
        }
    }

    static func undoToast() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot(
                kind: CoreErrorKindTestMapper.kind(for: error),
                userMessage: "Undo failed",
                severity: .medium,
                suggestedAction: "View details in Undo history.",
                recoverability: .refreshRequired,
                rawContext: "undo-toast undo-action-log undo-action-log"
            )
        }
    }

    static func undoHistory() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot(
                kind: CoreErrorKindTestMapper.kind(for: error),
                userMessage: "Undo failed",
                severity: .medium,
                suggestedAction: "View details in Undo history.",
                recoverability: .refreshRequired,
                rawContext: "undo-history undo-action-log undo-action-log"
            )
        }
    }
}
