@testable import AreaMatrix
import Foundation

enum RepositorySettingsLoaderResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

actor RepositorySettingsRecordingLoader: CoreConfigurationLoading {
    private var results: [RepositorySettingsLoaderResult]
    private var paths: [String] = []

    init(results: [RepositorySettingsLoaderResult]) {
        self.results = results
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        let result = results.isEmpty ? .failure(CoreError.Internal(message: "missing config")) : results.removeFirst()
        switch result {
        case let .success(config):
            return config
        case let .failure(error):
            throw error
        }
    }

    func requestedPaths() -> [String] {
        paths
    }
}

enum RepositorySettingsUpdateResult {
    case success
    case failure(Error)
}

actor RepositorySettingsRecordingUpdater: CoreConfigurationUpdating {
    struct Request: Equatable {
        var repoPath: String
        var config: RepoConfigSnapshot
    }

    private let result: RepositorySettingsUpdateResult
    private var recordedRequests: [Request] = []

    init(result: RepositorySettingsUpdateResult) {
        self.result = result
    }

    func updateConfig(repoPath: String, newConfig: RepoConfigSnapshot) async throws {
        recordedRequests.append(Request(repoPath: repoPath, config: newConfig))
        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

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
            rawContext: "S1-27 C1-04"
        )
    }

    func mappedErrors() -> [CoreError] {
        errors
    }
}

enum RepositorySettingsRevealResult {
    case success
    case failure(Error)
}

@MainActor
final class RepositorySettingsRecordingFileRevealer: RepositoryFileRevealing {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private let result: RepositorySettingsRevealResult
    private(set) var requests: [Request] = []

    init(result: RepositorySettingsRevealResult = .success) {
        self.result = result
    }

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        }
    }
}

func temporaryRepositorySettingsRepo() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixRepositorySettings-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func createRepositorySettingsMetadataDatabaseMarker(in repoURL: URL) throws {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    try FileManager.default.createDirectory(at: metadataURL, withIntermediateDirectories: true)
    try Data().write(to: metadataURL.appendingPathComponent("index.db"))
}

func removeRepositorySettingsMetadataDatabaseSidecars(in repoURL: URL) {
    let metadataURL = repoURL.appendingPathComponent(".areamatrix", isDirectory: true)
    for name in ["index.db-wal", "index.db-shm"] {
        try? FileManager.default.removeItem(at: metadataURL.appendingPathComponent(name))
    }
}
