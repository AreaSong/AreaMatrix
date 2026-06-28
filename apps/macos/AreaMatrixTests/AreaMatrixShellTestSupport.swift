@testable import AreaMatrix
import XCTest

struct ShellStaticSettingsReader: AppSettingsReading {
    let repoPath: String?
    var lastOpenedAtByRepoPath: [String: Int64] = [:]

    func configuredRepoPath() -> String? {
        repoPath
    }

    func lastSuccessfulRepoOpenAt(repoPath: String) -> Int64? {
        lastOpenedAtByRepoPath[repoPath]
    }
}

final class ShellRecordingSettingsWriter: AppSettingsWriting {
    private(set) var savedRepoPaths: [String] = []
    private(set) var successfulRepoOpens: [(repoPath: String, openedAt: Int64)] = []

    func saveConfiguredRepoPath(_ repoPath: String) {
        savedRepoPaths.append(repoPath)
    }

    func saveSuccessfulRepoOpen(repoPath: String, openedAt: Int64) {
        successfulRepoOpens.append((repoPath: repoPath, openedAt: openedAt))
    }
}

enum ShellRecordingResult {
    case success(RepoConfigSnapshot)
    case failure(Error)
}

enum ShellRecordingRepositoryOpenResult {
    case success(RepositoryOpeningResult)
    case failure(Error)
}

actor ShellRecordingConfigLoader: CoreConfigurationLoading {
    private let result: ShellRecordingResult
    private var paths: [String] = []

    init(result: ShellRecordingResult) {
        self.result = result
    }

    func loadConfig(repoPath: String) async throws -> RepoConfigSnapshot {
        paths.append(repoPath)
        switch result {
        case let .success(config):
            return config
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

actor ShellRecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: ShellRecordingRepositoryOpenResult
    private var configuredPaths: [String] = []

    init(result: ShellRecordingRepositoryOpenResult) {
        self.result = result
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        try await openConfiguredRepository(repoPath: repoPath)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        configuredPaths.append(repoPath)
        switch result {
        case let .success(opening):
            return opening
        case let .failure(error):
            throw error
        }
    }

    func requestedConfiguredRepoPaths() -> [String] {
        configuredPaths
    }
}

enum ShellRecordingPathValidationResult {
    case success(RepoPathValidationSnapshot)
    case failure(Error)
}

actor ShellRecordingPathValidator: CoreRepositoryPathValidating {
    private let result: ShellRecordingPathValidationResult
    private var paths: [String] = []

    init(result: ShellRecordingPathValidationResult) {
        self.result = result
    }

    func validateRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        paths.append(repoPath)
        switch result {
        case let .success(validation):
            return validation
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

actor ShellRecordingInitializedPathValidator: CoreInitializedRepositoryPathValidating {
    private let result: ShellRecordingPathValidationResult
    private var paths: [String] = []

    init(result: ShellRecordingPathValidationResult) {
        self.result = result
    }

    func validateInitializedRepoPath(repoPath: String) async throws -> RepoPathValidationSnapshot {
        paths.append(repoPath)
        switch result {
        case let .success(validation):
            return validation
        case let .failure(error):
            throw error
        }
    }

    func requestedRepoPaths() -> [String] {
        paths
    }
}

struct ShellExternalRemovalRequest: Equatable {
    var repoPath: String
    var relativePath: String
    var fsEventID: Int64
}

actor ShellRecordingExternalChangesSyncer: CoreExternalChangesSyncing {
    private let result: Result<SyncResultSnapshot, Error>
    private var requests: [ShellExternalRemovalRequest] = []
    private var createdRequests: [ShellExternalRemovalRequest] = []
    private var renamedRequests: [ShellExternalRemovalRequest] = []

    init(result: Result<SyncResultSnapshot, Error>) {
        self.result = result
    }

    func syncExternalCreated(repoPath: String, relativePath: String,
                             fsEventID: Int64) async throws -> SyncResultSnapshot {
        createdRequests.append(ShellExternalRemovalRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func syncExternalRenamed(repoPath: String, relativePath: String,
                             fsEventID: Int64) async throws -> SyncResultSnapshot {
        renamedRequests.append(ShellExternalRemovalRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func syncExternalRemoved(repoPath: String, relativePath: String,
                             fsEventID: Int64) async throws -> SyncResultSnapshot {
        requests.append(ShellExternalRemovalRequest(
            repoPath: repoPath,
            relativePath: relativePath,
            fsEventID: fsEventID
        ))
        switch result {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func recordedRequests() -> [ShellExternalRemovalRequest] {
        requests
    }

    func recordedCreatedRequests() -> [ShellExternalRemovalRequest] {
        createdRequests
    }

    func recordedRenamedRequests() -> [ShellExternalRemovalRequest] {
        renamedRequests
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        nil
    }

    func setFSEventCursor(repoPath _: String, lastEventID _: Int64) async throws {}
}

actor ShellRecordingDiagnosticsCollector: CoreDiagnosticsCollecting {
    private let result: Result<DiagnosticsSnapshotSnapshot, Error>
    private var repoPaths: [String] = []

    init(result: Result<DiagnosticsSnapshotSnapshot, Error>) {
        self.result = result
    }

    func createDiagnosticsSnapshot(repoPath: String) async throws -> DiagnosticsSnapshotSnapshot {
        repoPaths.append(repoPath)
        return try result.get()
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }
}

struct ShellFailingWelcomeHelpOpener: WelcomeHelpOpening {
    func openWelcomeHelp() throws {
        throw WelcomeHelpError.helpDocumentUnavailable
    }
}

@MainActor
final class ShellRecordingPathCopier: RepositoryPathCopying {
    private(set) var requests: [(repoPath: String, relativePath: String)] = []
    private(set) var multiPathRequests: [(repoPath: String, relativePaths: [String])] = []

    func copyPath(repoPath: String, relativePath: String) throws {
        requests.append((repoPath: repoPath, relativePath: relativePath))
    }

    func copyPaths(repoPath: String, relativePaths: [String]) throws {
        multiPathRequests.append((repoPath: repoPath, relativePaths: relativePaths))
    }
}

struct ShellExistingRepoMetadataReader: ExistingRepositoryMetadataReading {
    let schemaVersion: Int64
    var lastOpenedAt: Int64?
    var configuredRepoPath: String?

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        ExistingRepositoryMetadataSnapshot(
            schemaVersion: schemaVersion,
            lastOpenedAt: lastOpenedAt,
            configuredRepoPath: configuredRepoPath
        )
    }
}

@MainActor
final class ShellRecordingDirectoryPicker: RepositoryDirectoryPicking {
    private let selectedURL: URL?
    private(set) var chooseCount = 0

    init(selectedURL: URL?) {
        self.selectedURL = selectedURL
    }

    func chooseDirectory() -> URL? {
        chooseCount += 1
        return selectedURL
    }
}
