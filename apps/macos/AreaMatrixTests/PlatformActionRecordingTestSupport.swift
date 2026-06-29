@testable import AreaMatrix

@MainActor
final class RecordingRepositoryFinderOpener: RepositoryFinderOpening {
    private let result: Result<Void, Error>
    private(set) var repoPaths: [String] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openRepositoryInFinder(repoPath: String) throws {
        repoPaths.append(repoPath)
        try result.get()
    }
}

struct StaticSettingsReader: AppSettingsReading {
    let repoPath: String?

    func configuredRepoPath() -> String? {
        repoPath
    }
}

struct StaticAppVersionReader: AppVersionReading {
    let version: String

    func appVersion() -> String {
        version
    }
}

struct StaticICloudStatusDetector: ICloudStatusDetecting {
    let snapshot: IntegrationsICloudSnapshot

    init(snapshot: IntegrationsICloudSnapshot = IntegrationsICloudSnapshot(
        repositoryLocation: .localFolder,
        iCloudStatus: .unavailable
    )) {
        self.snapshot = snapshot
    }

    func snapshot(repoPath _: String, config _: RepoConfigSnapshot) async -> IntegrationsICloudSnapshot {
        snapshot
    }
}

@MainActor
final class RecordingRepositoryFileRevealer: RepositoryFileRevealing {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private let result: Result<Void, Error>
    private(set) var requests: [Request] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
        try result.get()
    }
}

@MainActor
final class RecordingRepositoryFileOpener: RepositoryFileOpening {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private let result: Result<Void, Error>
    private(set) var requests: [Request] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
        try result.get()
    }
}

@MainActor
final class RecordingAccessibilityAnnouncer: AccessibilityAnnouncing {
    private(set) var announcements: [String] = []

    var messages: [String] {
        announcements
    }

    func announce(_ message: String) {
        announcements.append(message)
    }
}

struct NoopAccessibilityAnnouncer: AccessibilityAnnouncing {
    @MainActor
    func announce(_: String) {}
}

struct NoopWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {}
}

struct NoopRepositoryIgnoreRulesManager: RepositoryIgnoreRulesManaging {
    @MainActor
    func openIgnoreRules(repoPath _: String) throws {}

    @MainActor
    func createDefaultIgnoreRules(repoPath _: String) throws {}
}

struct NoopICloudHelpOpener: ICloudHelpOpening {
    @MainActor
    func openICloudHelp() throws {}
}

struct StaticOnboardingSystemCapabilityChecker: OnboardingSystemCapabilityChecking {
    var isTrashAvailableValue = true
    var repositoryFinderAvailabilityByPath: [String: Bool] = [:]

    func isTrashAvailable() -> Bool {
        isTrashAvailableValue
    }

    func repositoryFinderAvailability(repoPath: String) -> Bool {
        repositoryFinderAvailabilityByPath[repoPath] ?? true
    }
}

struct NoopAboutExternalLinkOpener: AboutExternalLinkOpening {
    @MainActor
    func open(link: AboutExternalLink) throws -> String {
        link.urlString
    }
}

struct NoopAboutDiagnosticsRevealer: AboutDiagnosticsRevealing {
    @MainActor
    func revealDiagnostics(at _: String) throws {}
}
