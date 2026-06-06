import Foundation
@testable import AreaMatrixIOS

func makeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixIOSConnectRepository-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class FakeMobileRepositoryCoreBridge: MobileRepositoryCoreBridge, @unchecked Sendable {
    private let result: Result<MobileRepositoryValidation, MobileRepositoryConnectionError>
    private let cloudState: Result<MobileCloudStorageState, MobileRepositoryConnectionError>
    private(set) var validatedPaths: [String] = []
    private(set) var detectedCloudStatePaths: [String] = []
    private(set) var loadedConfigPaths: [String] = []
    private(set) var initializedPaths: [String] = []
    private(set) var adoptedPaths: [String] = []

    init(
        validation: MobileRepositoryValidation,
        cloudState: MobileCloudStorageState? = nil
    ) {
        result = .success(validation)
        self.cloudState = .success(cloudState ?? .local(path: validation.repoPath))
    }

    init(
        validation: MobileRepositoryValidation,
        cloudError: MobileRepositoryConnectionError
    ) {
        result = .success(validation)
        cloudState = .failure(cloudError)
    }

    init(error: MobileRepositoryConnectionError) {
        result = .failure(error)
        cloudState = .failure(error)
    }

    func validateRepoPath(repoPath: String) async throws -> MobileRepositoryValidation {
        validatedPaths.append(repoPath)
        return try result.get()
    }

    func detectCloudStorageState(repoPath: String) async throws -> MobileCloudStorageState {
        detectedCloudStatePaths.append(repoPath)
        return try cloudState.get()
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        initializedPaths.append(repoPath)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
    }

    func loadConfig(repoPath: String) async throws -> MobileRepositoryConfig {
        loadedConfigPaths.append(repoPath)
        return MobileRepositoryConfig(repoPath: repoPath, defaultMode: "Copied", locale: "zh-Hans")
    }
}

actor FakeRepositoryAccessService: RepositoryAccessServicing {
    private let resolveError: MobileRepositoryConnectionError?
    private let iCloudDriveAvailable: Bool
    private let repositories: [RecentRepository]
    private(set) var persistedPaths: [String] = []
    private(set) var resolvedRecentPaths: [String] = []

    init(
        resolveError: MobileRepositoryConnectionError? = nil,
        iCloudDriveAvailable: Bool = true,
        repositories: [RecentRepository] = []
    ) {
        self.resolveError = resolveError
        self.iCloudDriveAvailable = iCloudDriveAvailable
        self.repositories = repositories
    }

    func recentRepositories() async -> [RecentRepository] {
        repositories
    }

    func isICloudDriveAvailable() async -> Bool {
        iCloudDriveAvailable
    }

    func beginAccessing(_ url: URL) async throws -> RepositoryScopedAccess {
        RepositoryScopedAccess(url: url) {}
    }

    func persistedPathSnapshot() -> [String] {
        persistedPaths
    }

    func resolvedRecentPathSnapshot() -> [String] {
        resolvedRecentPaths
    }

    func persistBookmark(for url: URL, lastOpenedAt: Date) async throws -> RepositoryBookmark {
        persistedPaths.append(url.path)
        return RepositoryBookmark(
            url: url,
            displayName: url.lastPathComponent,
            pathDisplay: url.path,
            lastOpenedAt: lastOpenedAt
        )
    }

    func resolveBookmark(for recent: RecentRepository) async throws -> URL {
        resolvedRecentPaths.append(recent.pathDisplay)
        if let resolveError {
            throw resolveError
        }
        return URL(fileURLWithPath: recent.pathDisplay)
    }
}

extension MobileCloudStorageState {
    static func local(path: String) -> MobileCloudStorageState {
        fixture(path: path, providerKind: .local, risk: .noRisk)
    }

    static func iCloudAccessible(path: String) -> MobileCloudStorageState {
        fixture(path: path, providerKind: .iCloudDrive, risk: .medium)
    }

    static func iCloudAccessExpired(path: String) -> MobileCloudStorageState {
        fixture(
            path: path,
            providerKind: .iCloudDrive,
            risk: .medium,
            permissionState: .accessExpired,
            recommendedAction: .reconnectFolder,
            requiresReconnect: true
        )
    }

    static func iCloudPlaceholder(path: String) -> MobileCloudStorageState {
        fixture(
            path: path,
            providerKind: .iCloudDrive,
            risk: .medium,
            placeholderState: .placeholder,
            recommendedAction: .retryStatusCheck,
            canRetry: true
        )
    }

    static func iCloudPermissionDenied(path: String) -> MobileCloudStorageState {
        fixture(
            path: path,
            providerKind: .iCloudDrive,
            risk: .high,
            permissionState: .permissionDenied,
            recommendedAction: .reconnectFolder,
            requiresReconnect: true
        )
    }

    static func fixture(
        path: String,
        providerKind: MobileCloudStorageProviderKind,
        risk: MobileCloudStorageRiskLevel,
        placeholderState: MobileCloudPlaceholderState = .notPlaceholder,
        permissionState: MobileCloudPermissionState = .accessible,
        recommendedAction: MobileCloudStorageRecommendedAction = .none,
        requiresReconnect: Bool = false,
        canRetry: Bool = false
    ) -> MobileCloudStorageState {
        MobileCloudStorageState(
            repoPath: path,
            providerKind: providerKind,
            risk: risk,
            placeholderState: placeholderState,
            permissionState: permissionState,
            statusSummary: "Cloud status for \(path)",
            riskReasons: [],
            recommendedAction: recommendedAction,
            requiresNoticeAcknowledgement: false,
            noticeAcknowledged: false,
            canRetry: canRetry,
            requiresReconnect: requiresReconnect
        )
    }
}

extension MobileRepositoryValidation {
    static func initialized(path: String) -> MobileRepositoryValidation {
        fixture(path: path, isEmpty: false, isInitialized: true, recommendedMode: nil)
    }

    static func emptyDirectory(path: String) -> MobileRepositoryValidation {
        fixture(path: path, isEmpty: true, isInitialized: false, recommendedMode: .createEmpty)
    }

    static func nonEmptyDirectory(path: String) -> MobileRepositoryValidation {
        fixture(
            path: path,
            isEmpty: false,
            isInitialized: false,
            recommendedMode: .adoptExisting,
            issues: [.nonEmptyDirectory]
        )
    }

    static func selectedFile(path: String) -> MobileRepositoryValidation {
        fixture(
            path: path,
            isDirectory: false,
            isEmpty: false,
            isInitialized: false,
            recommendedMode: nil,
            issues: [.notDirectory]
        )
    }

    static func fixture(
        path: String,
        exists: Bool = true,
        isDirectory: Bool = true,
        isReadable: Bool = true,
        isWritable: Bool = true,
        isEmpty: Bool,
        isInitialized: Bool,
        recommendedMode: MobileRepositoryInitMode?,
        issues: [MobileRepositoryPathIssue] = []
    ) -> MobileRepositoryValidation {
        MobileRepositoryValidation(
            repoPath: path,
            exists: exists,
            isDirectory: isDirectory,
            isReadable: isReadable,
            isWritable: isWritable,
            isEmpty: isEmpty,
            isInitialized: isInitialized,
            isInsideAreaMatrix: false,
            isICloudPath: path.contains("Mobile Documents"),
            isOneDrivePath: path.localizedCaseInsensitiveContains("OneDrive"),
            platformPathKind: path.contains("Mobile Documents") ? .iCloudDrive : .local,
            isCaseSensitivePath: true,
            hasUnfinishedScanSession: issues.contains(.unfinishedScanSession),
            recommendedMode: recommendedMode,
            issues: issues
        )
    }
}
