public enum BatchTagApplyNormalizationResult: Equatable, Sendable {
    case success([String])
    case failure(String)
}

public struct BatchTagPendingState: Equatable, Sendable {
    public var input: String
    public var pendingTags: [String]
    public var fieldError: String?

    public init(input: String, pendingTags: [String], fieldError: String?) {
        self.input = input
        self.pendingTags = pendingTags
        self.fieldError = fieldError
    }
}
