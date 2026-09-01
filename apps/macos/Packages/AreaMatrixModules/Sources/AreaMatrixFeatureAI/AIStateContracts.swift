public enum AICallLogDateRangePreset: Equatable, Sendable {
    case any
    case last7Days
    case last30Days
    case thisYear
}

public enum RemoteProviderTestStatusState: String, Equatable, Sendable {
    case succeeded
    case providerRejected
    case connectionFailed
    case unsupportedProvider
}

public struct RemoteProviderDisableRequestState: Equatable, Sendable {
    public var removeStoredCredential: Bool

    public init(removeStoredCredential: Bool) {
        self.removeStoredCredential = removeStoredCredential
    }
}

public enum AIClassificationContextPolicyState: Equatable, Sendable {
    case fileNameOnly
    case fileNameAndPath
    case limitedTextSummary
}

public enum AIClassificationSuggestionStatusState: Equatable, Sendable {
    case suggested
    case noSuggestion
    case skipped
    case unavailable
}

// swiftlint:disable:next type_name
public enum AIClassificationSuggestionSkipReasonState: Equatable, Sendable {
    case aiDisabled
    case featureDisabled
    case ruleResultConfident
    case noEligibleContext
    case privacyRule
    case providerUnavailable
}

public struct AIClassificationSuggestionRequestState: Equatable, Sendable {
    public var fileID: Int64
    public var contextPolicy: AIClassificationContextPolicyState
    public var privacyPolicyRef: String?

    public init(
        fileID: Int64,
        contextPolicy: AIClassificationContextPolicyState,
        privacyPolicyRef: String? = nil
    ) {
        self.fileID = fileID
        self.contextPolicy = contextPolicy
        self.privacyPolicyRef = privacyPolicyRef
    }
}
