import Foundation

public protocol OnboardingSystemCapabilityChecking: Sendable {
    func isTrashAvailable() -> Bool
    func repositoryFinderAvailability(repoPath: String) -> Bool
}

public enum ImportEntryDestination: Equatable, Sendable {
    case autoClassify
    case category(String)
    case repositoryRoot
}

public enum ImportEntryKind: Equatable, Sendable {
    case singleFile
    case multipleItems(Int)
    case folder

    public static func resolved(
        for urls: [URL],
        isDirectory: (URL) -> Bool
    ) -> ImportEntryKind {
        if urls.contains(where: isDirectory) { return .folder }
        return urls.count == 1 ? .singleFile : .multipleItems(urls.count)
    }
}

public struct ImportFolderSkippedRule: Equatable, Identifiable, Sendable {
    public var label: String
    public var count: Int

    public init(label: String, count: Int) {
        self.label = label
        self.count = count
    }

    public var id: String {
        label
    }
}

public struct ImportFolderScanError: Equatable, Identifiable, Sendable {
    public var path: String
    public var message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }

    public var id: String {
        "\(path)::\(message)"
    }
}

public enum ImportProgressRecoveryPhase: Equatable, Sendable {
    case unavailable
    case checking
    case retryAllowed
    case retryBlocked(String)
}

public enum ImportProgressDiagnosticsPhase: Equatable, Sendable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected
    case failed
}

public enum ImportProgressStopPhase: Equatable, Sendable {
    case idle
    case stopping
    case stopped
}
