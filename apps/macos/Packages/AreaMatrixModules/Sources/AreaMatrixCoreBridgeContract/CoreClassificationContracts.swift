/// Stable local-classification capability surface.
///
/// Classification execution and any file/import policy remain App/Core-owned;
/// this module only publishes the value contract consumed by feature models.
public protocol CoreCategoryPredicting: Sendable {
    func predictCategory(repoPath: String, filename: String) async throws -> ClassifyResultSnapshot
}

public enum ClassifyReasonSnapshot: String, Equatable, Sendable {
    case keyword = "Keyword"
    case `extension` = "Extension"
    case aiPredicted = "AiPredicted"
    case `default` = "Default"
}

public struct ClassifyResultSnapshot: Equatable, Sendable {
    public let category: String
    public let suggestedName: String
    public let reason: ClassifyReasonSnapshot
    public let confidence: Float

    public init(category: String, suggestedName: String, reason: ClassifyReasonSnapshot, confidence: Float) {
        self.category = category
        self.suggestedName = suggestedName
        self.reason = reason
        self.confidence = confidence
    }
}
