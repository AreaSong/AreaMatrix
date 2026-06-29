@testable import AreaMatrix
import Foundation

enum RepositorySettingsMetadataResult {
    case success(ExistingRepositoryMetadataSnapshot)
    case failure(Error)
}

actor RepoSettingsMetadataReader: ExistingRepositoryMetadataReading {
    private var results: [RepositorySettingsMetadataResult]

    init(results: [RepositorySettingsMetadataResult]) {
        self.results = results
    }

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        guard !results.isEmpty else {
            throw CoreError.Internal(message: "missing metadata test result")
        }

        switch results.removeFirst() {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }
}

enum RepositorySettingsOpeningResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

actor RepoSettingsRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: RepositorySettingsOpeningResult

    init(result: RepositorySettingsOpeningResult) {
        self.result = result
    }

    func openConfiguredRepository(repoPath _: String) async throws -> RepositoryOpeningResult {
        try resolve()
    }

    func openEmptyRepository(repoPath _: String) async throws -> RepositoryOpeningResult {
        try resolve()
    }

    func openAdoptedRepository(repoPath _: String) async throws -> RepositoryOpeningResult {
        try resolve()
    }

    private func resolve() throws -> RepositoryOpeningResult {
        switch result {
        case let .success(opening):
            return opening
        case let .failure(error):
            throw error
        }
    }
}

enum RepositorySettingsScanSessionResult {
    case success(ScanSessionSnapshot?)
    case failure(Error)
}

actor RepoSettingsScanSessionReader: CoreScanSessionReading {
    private let result: RepositorySettingsScanSessionResult

    init(result: RepositorySettingsScanSessionResult) {
        self.result = result
    }

    func latestScanSession(repoPath _: String) async throws -> ScanSessionSnapshot? {
        switch result {
        case let .success(session):
            return session
        case let .failure(error):
            throw error
        }
    }
}

final class RecordingRepoMetadataPresenceChecker: RepoMetadataPresenceChecking {
    private(set) var repoPaths: [String] = []
    private let presence: RepoMetadataPresence

    init(presence: RepoMetadataPresence) {
        self.presence = presence
    }

    func metadataPresence(repoPath: String) -> RepoMetadataPresence {
        repoPaths.append(repoPath)
        return presence
    }
}

actor RepositorySettingsStaticErrorMapper: CoreErrorMapping {
    private var errors: [CoreError] = []

    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        errors.append(error)
        let userMessage: String
        let kind: CoreErrorKindSnapshot
        switch error {
        case .Db:
            kind = .db
            userMessage = "数据库错误"
        case .PermissionDenied:
            kind = .permissionDenied
            userMessage = "权限错误"
        default:
            kind = .config
            userMessage = "配置错误"
        }

        return CoreErrorMappingSnapshot(
            kind: kind,
            userMessage: userMessage,
            severity: .medium,
            suggestedAction: "Retry status",
            recoverability: .retryable,
            rawContext: "repository-settings repository-settings-core"
        )
    }

    func mappedErrors() -> [CoreError] {
        errors
    }
}

struct RepositorySettingsCapabilityRequest: Equatable {
    var platform: PlatformIdSnapshot
    var appVersion: String
}

actor RepoSettingsCapabilityLoader: CorePlatformCapabilitiesLoading {
    private let result: Result<PlatformCapabilitiesSnapshot, Error>
    private var capturedRequests: [RepositorySettingsCapabilityRequest] = []

    init(result: Result<PlatformCapabilitiesSnapshot, Error>) {
        self.result = result
    }

    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        capturedRequests.append(RepositorySettingsCapabilityRequest(
            platform: platform,
            appVersion: appVersion
        ))
        return try result.get()
    }

    func requests() -> [RepositorySettingsCapabilityRequest] {
        capturedRequests
    }
}

func repositorySettingsCapabilitySupport(
    status: PlatformCapabilityStatusSnapshot = .available,
    uiEnabled: Bool = true,
    requiresPermission: Bool = false,
    reason: String? = nil
) -> PlatformCapabilitySupportSnapshot {
    PlatformCapabilitySupportSnapshot(
        status: status,
        uiEnabled: uiEnabled,
        requiresPermission: requiresPermission,
        reason: reason
    )
}

func repositorySettingsCapabilitiesFixture(
    watcher: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    trash: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    cloudPlaceholder: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport(),
    securityBookmark: PlatformCapabilitySupportSnapshot = repositorySettingsCapabilitySupport()
) -> PlatformCapabilitiesSnapshot {
    PlatformCapabilitiesSnapshot(
        platform: .macos,
        appVersion: "1",
        watcher: watcher,
        trash: trash,
        shareExtension: repositorySettingsCapabilitySupport(status: .notAvailable, uiEnabled: false),
        cloudPlaceholder: cloudPlaceholder,
        securityBookmark: securityBookmark
    )
}

func temporaryRepositorySettingsRepo() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixRepositorySettings")
}

func createRepositorySettingsMetadataDatabaseMarker(in repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    try Data().write(to: metadataURL.appendingPathComponent("index.db"))
}

func removeRepositorySettingsMetadataDatabaseSidecars(in repoURL: URL) {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    for name in ["index.db-wal", "index.db-shm"] {
        try? removeTestTemporaryItem(metadataURL.appendingPathComponent(name))
    }
}
