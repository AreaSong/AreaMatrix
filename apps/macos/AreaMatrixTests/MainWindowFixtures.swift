@testable import AreaMatrix

extension CoreErrorMappingSnapshot {
    static func mainWindowMapping(
        kind: CoreErrorKindSnapshot,
        severity: CoreErrorSeveritySnapshot = .high,
        recoverability: CoreErrorRecoverabilitySnapshot = .userActionRequired,
        rawContext: String = "main-window"
    ) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: "mapped \(kind.rawValue)",
            severity: severity,
            suggestedAction: "mapped action",
            recoverability: recoverability,
            rawContext: rawContext
        )
    }
}
