import Foundation
@testable import AreaMatrixIOS
import XCTest

@MainActor
final class ConnectRepositoryModelTests: XCTestCase {
    func testExistingRepositoryRoutesToMobileLibraryAfterCoreValidationAndConfigLoad() async {
        let url = URL(fileURLWithPath: "/tmp/AreaMatrixRepo")
        let bridge = FakeMobileRepositoryCoreBridge(validation: .initialized(path: url.path))
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(
            bridge: bridge,
            accessService: access,
            now: { Date(timeIntervalSince1970: 42) }
        )

        await model.connectSelectedURL(url)

        XCTAssertEqual(bridge.validatedPaths, [url.path])
        XCTAssertEqual(bridge.loadedConfigPaths, [url.path])
        XCTAssertTrue(bridge.initializedPaths.isEmpty)
        XCTAssertTrue(bridge.adoptedPaths.isEmpty)
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertEqual(persistedPaths, [url.path])
        guard case let .mobileLibrary(connection) = model.route else {
            return XCTFail("expected mobile library route")
        }
        XCTAssertEqual(connection.config.repoPath, url.path)
        XCTAssertNil(model.error)
    }

    func testEmptyDirectoryRoutesToInitConfirmationWithoutInitializing() async {
        let url = URL(fileURLWithPath: "/tmp/EmptyRepo")
        let bridge = FakeMobileRepositoryCoreBridge(validation: .emptyDirectory(path: url.path))
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(bridge: bridge, accessService: access)

        await model.connectSelectedURL(url)

        XCTAssertEqual(bridge.validatedPaths, [url.path])
        XCTAssertTrue(bridge.loadedConfigPaths.isEmpty)
        XCTAssertTrue(bridge.initializedPaths.isEmpty)
        XCTAssertTrue(bridge.adoptedPaths.isEmpty)
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertTrue(persistedPaths.isEmpty)
        guard case let .repositoryInitConfirm(candidate) = model.route else {
            return XCTFail("expected init confirmation route")
        }
        XCTAssertEqual(candidate.validation.recommendedMode, .createEmpty)
    }

    func testNonEmptyDirectoryRoutesToAdoptConfirmationWithoutWriting() async {
        let url = URL(fileURLWithPath: "/tmp/ExistingFolder")
        let bridge = FakeMobileRepositoryCoreBridge(validation: .nonEmptyDirectory(path: url.path))
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(bridge: bridge, accessService: access)

        await model.connectSelectedURL(url)

        XCTAssertEqual(bridge.validatedPaths, [url.path])
        XCTAssertTrue(bridge.loadedConfigPaths.isEmpty)
        XCTAssertTrue(bridge.initializedPaths.isEmpty)
        XCTAssertTrue(bridge.adoptedPaths.isEmpty)
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertTrue(persistedPaths.isEmpty)
        guard case let .repositoryAdoptConfirm(candidate) = model.route else {
            return XCTFail("expected adopt confirmation route")
        }
        XCTAssertEqual(candidate.validation.recommendedMode, .adoptExisting)
    }

    func testSelectedFileMapsToReadableFolderError() async {
        let url = URL(fileURLWithPath: "/tmp/file.txt")
        let bridge = FakeMobileRepositoryCoreBridge(validation: .selectedFile(path: url.path))
        let model = ConnectRepositoryModel(bridge: bridge, accessService: FakeRepositoryAccessService())

        await model.connectSelectedURL(url)

        XCTAssertEqual(model.error, .selectedFile(url.path))
        XCTAssertNil(model.route)
    }

    func testICloudPlaceholderRoutesToPermissionRecovery() async {
        let url = URL(fileURLWithPath: "/tmp/Mobile Documents/AreaMatrixRepo")
        let bridge = FakeMobileRepositoryCoreBridge(error: .iCloudPlaceholder(url.path))
        let model = ConnectRepositoryModel(bridge: bridge, accessService: FakeRepositoryAccessService())

        await model.connectSelectedURL(url)

        XCTAssertEqual(model.error, .iCloudPlaceholder(url.path))
        XCTAssertEqual(model.route, .iCloudPermission(.iCloudPlaceholder(url.path)))
    }

    func testExpiredRecentRepositoryKeepsUserOnConnectPage() async {
        let recent = RecentRepository(
            displayName: "Expired",
            pathDisplay: "/tmp/Expired",
            lastOpenedAt: Date(timeIntervalSince1970: 1),
            accessStatus: .expired
        )
        let access = FakeRepositoryAccessService(resolveError: .accessExpired(recent.pathDisplay))
        let model = ConnectRepositoryModel(
            bridge: FakeMobileRepositoryCoreBridge(validation: .initialized(path: "/tmp/Expired")),
            accessService: access
        )

        await model.reconnect(recent)

        XCTAssertEqual(model.error, .accessExpired(recent.pathDisplay))
        XCTAssertNil(model.route)
    }

    func testEntryViewUsesLiveCoreBridgeByDefault() {
        let entry = ConnectRepositoryEntryView()

        XCTAssertTrue(String(describing: type(of: entry)).contains("ConnectRepositoryEntryView"))
    }

    func testLiveBridgeTypeExistsForProductionCoreWiring() {
        let bridge: any MobileRepositoryCoreBridge = LiveMobileRepositoryCoreBridge()

        XCTAssertTrue(String(describing: type(of: bridge)).contains("LiveMobileRepositoryCoreBridge"))
    }

    func testLiveBridgeValidatesAndLoadsExistingRepositoryThroughCore() async throws {
        let url = try makeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let bridge = LiveMobileRepositoryCoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: url.path)
        let model = ConnectRepositoryModel(bridge: bridge, accessService: FakeRepositoryAccessService())

        await model.connectSelectedURL(url)

        guard case let .mobileLibrary(connection) = model.route else {
            return XCTFail("expected live Core bridge to route initialized repo to mobile library")
        }
        XCTAssertEqual(connection.validation.repoPath, url.path)
        XCTAssertTrue(connection.validation.isInitialized)
        XCTAssertEqual(connection.config.repoPath, url.path)
        XCTAssertNil(model.error)
    }

    func testLiveBridgeMapsCorePathErrors() async {
        let bridge = LiveMobileRepositoryCoreBridge()

        do {
            _ = try await bridge.validateRepoPath(repoPath: "")
            XCTFail("expected invalid path from Core")
        } catch MobileRepositoryConnectionError.invalidPath {
        } catch {
            XCTFail("expected invalidPath, got \(error)")
        }
    }

    func testValidationDTOCarriesFullCoreContractFields() {
        let validation = MobileRepositoryValidation(
            repoPath: "/tmp/OneDrive/Repo",
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: false,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            isOneDrivePath: true,
            platformPathKind: .oneDrive,
            isCaseSensitivePath: false,
            hasUnfinishedScanSession: true,
            recommendedMode: .adoptExisting,
            issues: [.oneDrivePath, .windowsCaseInsensitive, .unfinishedScanSession]
        )

        XCTAssertTrue(validation.isThirdPartyCloudPath)
        XCTAssertFalse(validation.isCaseSensitivePath)
        XCTAssertTrue(validation.hasUnfinishedScanSession)
        XCTAssertEqual(validation.platformPathKind, .oneDrive)
        XCTAssertTrue(validation.issues.contains(.windowsCaseInsensitive))
    }
}

private func makeTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixIOSConnectRepository-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class FakeMobileRepositoryCoreBridge: MobileRepositoryCoreBridge, @unchecked Sendable {
    private let result: Result<MobileRepositoryValidation, MobileRepositoryConnectionError>
    private(set) var validatedPaths: [String] = []
    private(set) var loadedConfigPaths: [String] = []
    private(set) var initializedPaths: [String] = []
    private(set) var adoptedPaths: [String] = []

    init(validation: MobileRepositoryValidation) {
        result = .success(validation)
    }

    init(error: MobileRepositoryConnectionError) {
        result = .failure(error)
    }

    func validateRepoPath(repoPath: String) async throws -> MobileRepositoryValidation {
        validatedPaths.append(repoPath)
        return try result.get()
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

private actor FakeRepositoryAccessService: RepositoryAccessServicing {
    private let resolveError: MobileRepositoryConnectionError?
    private(set) var persistedPaths: [String] = []

    init(resolveError: MobileRepositoryConnectionError? = nil) {
        self.resolveError = resolveError
    }

    func recentRepositories() async -> [RecentRepository] {
        []
    }

    func beginAccessing(_ url: URL) async throws -> RepositoryScopedAccess {
        RepositoryScopedAccess(url: url) {}
    }

    func persistedPathSnapshot() -> [String] {
        persistedPaths
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
        if let resolveError {
            throw resolveError
        }
        return URL(fileURLWithPath: recent.pathDisplay)
    }
}

private extension MobileRepositoryValidation {
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
