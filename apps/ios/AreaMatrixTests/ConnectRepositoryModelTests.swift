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
        XCTAssertEqual(bridge.detectedCloudStatePaths, [url.path])
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
        XCTAssertEqual(bridge.detectedCloudStatePaths, [url.path])
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
        XCTAssertEqual(bridge.detectedCloudStatePaths, [url.path])
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

    func testCloudPermissionStateRoutesToICloudPermissionBeforeOpeningRepository() async {
        let url = URL(fileURLWithPath: "/tmp/Mobile Documents/AreaMatrixRepo")
        let bridge = FakeMobileRepositoryCoreBridge(
            validation: .initialized(path: url.path),
            cloudState: .iCloudAccessExpired(path: url.path)
        )
        let access = FakeRepositoryAccessService()
        let model = ConnectRepositoryModel(bridge: bridge, accessService: access)

        await model.connectSelectedURL(url)

        XCTAssertEqual(bridge.validatedPaths, [url.path])
        XCTAssertEqual(bridge.detectedCloudStatePaths, [url.path])
        XCTAssertTrue(bridge.loadedConfigPaths.isEmpty)
        XCTAssertEqual(model.latestCloudState, .iCloudAccessExpired(path: url.path))
        XCTAssertEqual(model.error, .accessExpired(url.path))
        XCTAssertEqual(model.route, .iCloudPermission(.accessExpired(url.path)))
        let persistedPaths = await access.persistedPathSnapshot()
        XCTAssertTrue(persistedPaths.isEmpty)
    }

    func testICloudCloudStateIsVisibleButDoesNotBlockAccessibleRepository() async {
        let url = URL(fileURLWithPath: "/tmp/Mobile Documents/AreaMatrixRepo")
        let bridge = FakeMobileRepositoryCoreBridge(
            validation: .initialized(path: url.path),
            cloudState: .iCloudAccessible(path: url.path)
        )
        let model = ConnectRepositoryModel(bridge: bridge, accessService: FakeRepositoryAccessService())

        await model.connectSelectedURL(url)

        XCTAssertEqual(model.latestCloudState, .iCloudAccessible(path: url.path))
        XCTAssertNil(model.error)
        guard case .mobileLibrary = model.route else {
            return XCTFail("expected accessible iCloud repository to open")
        }
    }

    func testCloudDetectionPermissionErrorRoutesOnlyForICloudPath() async {
        let url = URL(fileURLWithPath: "/tmp/Mobile Documents/AreaMatrixRepo")
        let bridge = FakeMobileRepositoryCoreBridge(
            validation: .initialized(path: url.path),
            cloudError: .permissionDenied(url.path)
        )
        let model = ConnectRepositoryModel(bridge: bridge, accessService: FakeRepositoryAccessService())

        await model.connectSelectedURL(url)

        XCTAssertEqual(bridge.detectedCloudStatePaths, [url.path])
        XCTAssertEqual(model.error, .permissionDenied(url.path))
        XCTAssertEqual(model.route, .iCloudPermission(.permissionDenied(url.path)))
    }

    func testICloudUnavailablePrimaryEntryRoutesToPermissionPageWithoutOpeningPicker() async {
        let unavailableMessage = "iCloud Drive 不可用，"
            + "请在系统设置中启用 iCloud Drive 后重试。"
        let bridge = FakeMobileRepositoryCoreBridge(validation: .initialized(path: "/tmp/AreaMatrixRepo"))
        let access = FakeRepositoryAccessService(iCloudDriveAvailable: false)
        let model = ConnectRepositoryModel(bridge: bridge, accessService: access)

        let shouldOpenPicker = await model.connectICloudRepository()

        XCTAssertFalse(shouldOpenPicker)
        XCTAssertTrue(bridge.validatedPaths.isEmpty)
        XCTAssertEqual(model.error, .unavailable(unavailableMessage))
        XCTAssertEqual(model.route, .iCloudPermission(.unavailable(unavailableMessage)))
    }

    func testICloudAvailablePrimaryEntryRequestsFolderPicker() async {
        let bridge = FakeMobileRepositoryCoreBridge(validation: .initialized(path: "/tmp/AreaMatrixRepo"))
        let model = ConnectRepositoryModel(bridge: bridge, accessService: FakeRepositoryAccessService())

        let shouldOpenPicker = await model.connectICloudRepository()

        XCTAssertTrue(shouldOpenPicker)
        XCTAssertTrue(bridge.validatedPaths.isEmpty)
        XCTAssertNil(model.error)
        XCTAssertNil(model.route)
    }

    func testExpiredRecentRepositoryRequestsPickerReconnectWithoutResolvingBookmark() async {
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

        let shouldOpenPicker = await model.reconnect(recent)

        XCTAssertTrue(shouldOpenPicker)
        XCTAssertNil(model.error)
        XCTAssertNil(model.route)
        let resolvedPaths = await access.resolvedRecentPathSnapshot()
        XCTAssertTrue(resolvedPaths.isEmpty)
    }

    func testStaleRecentBookmarkRequestsPickerReconnectAfterAccessExpiredError() async {
        let recent = RecentRepository(
            displayName: "Stale",
            pathDisplay: "/tmp/Stale",
            lastOpenedAt: Date(timeIntervalSince1970: 1),
            accessStatus: .available
        )
        let access = FakeRepositoryAccessService(resolveError: .accessExpired(recent.pathDisplay))
        let model = ConnectRepositoryModel(
            bridge: FakeMobileRepositoryCoreBridge(validation: .initialized(path: recent.pathDisplay)),
            accessService: access
        )

        let shouldOpenPicker = await model.reconnect(recent)

        XCTAssertTrue(shouldOpenPicker)
        XCTAssertEqual(model.error, .accessExpired(recent.pathDisplay))
        XCTAssertNil(model.route)
        let resolvedPaths = await access.resolvedRecentPathSnapshot()
        XCTAssertEqual(resolvedPaths, [recent.pathDisplay])
    }

    func testDismissRouteClearsRouteAfterNavigationDismissal() async {
        let url = URL(fileURLWithPath: "/tmp/AreaMatrixRepo")
        let model = ConnectRepositoryModel(
            bridge: FakeMobileRepositoryCoreBridge(validation: .initialized(path: url.path)),
            accessService: FakeRepositoryAccessService()
        )

        await model.connectSelectedURL(url)
        guard case .mobileLibrary = model.route else {
            return XCTFail("expected mobile library route")
        }

        model.dismissRoute()

        XCTAssertNil(model.route)
    }

    func testRouteCoordinatorPresentsAndDismissesProductionRoutes() {
        let route = mobileLibraryRoute(path: "/tmp/AreaMatrixRepo")
        let coordinator = ConnectRepositoryRouteCoordinator()

        coordinator.update(route)

        XCTAssertTrue(coordinator.isPresented)
        XCTAssertEqual(coordinator.activeRoute, route)

        coordinator.dismiss()

        XCTAssertFalse(coordinator.isPresented)
        XCTAssertNil(coordinator.activeRoute)
    }

    func testRouteDestinationContentCoversConnectRepositoryExitRoutes() {
        let mobileContent = ConnectRepositoryRouteDestinationContent(
            route: mobileLibraryRoute(path: "/tmp/AreaMatrixRepo")
        )
        let initContent = ConnectRepositoryRouteDestinationContent(
            route: .repositoryInitConfirm(
                candidate(path: "/tmp/Empty", validation: .emptyDirectory(path: "/tmp/Empty"))
            )
        )
        let adoptContent = ConnectRepositoryRouteDestinationContent(
            route: .repositoryAdoptConfirm(
                candidate(path: "/tmp/Existing", validation: .nonEmptyDirectory(path: "/tmp/Existing"))
            )
        )
        let iCloudContent = ConnectRepositoryRouteDestinationContent(
            route: .iCloudPermission(.accessExpired("/tmp/Mobile Documents/AreaMatrixRepo"))
        )

        XCTAssertEqual(mobileContent.title, "Mobile Library")
        XCTAssertEqual(mobileContent.pathText, "/tmp/AreaMatrixRepo")
        XCTAssertEqual(initContent.title, "Initialize Repository")
        XCTAssertEqual(initContent.pathText, "/tmp/Empty")
        XCTAssertEqual(adoptContent.title, "Adopt Repository")
        XCTAssertEqual(adoptContent.pathText, "/tmp/Existing")
        XCTAssertEqual(iCloudContent.title, "iCloud Permission")
        XCTAssertNil(iCloudContent.pathText)
    }

    func testRepositoryHelpContentExplainsFolderSafetyAndICloudUse() {
        let content = ConnectRepositoryHelpContent.repositoryHelp
        let helpText = content.rows.joined(separator: " ")

        XCTAssertEqual(content.title, "Repository Help")
        XCTAssertTrue(helpText.contains("normal folder"))
        XCTAssertTrue(helpText.contains("before you confirm"))
        XCTAssertTrue(helpText.contains("iCloud Drive"))
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

    func testLiveBridgeDetectsCloudStorageStateThroughCore() async throws {
        let url = try makeTemporaryRepositoryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let bridge = LiveMobileRepositoryCoreBridge()

        let state = try await bridge.detectCloudStorageState(repoPath: url.path)

        XCTAssertEqual(state.repoPath, url.path)
        XCTAssertEqual(state.providerKind, .local)
        XCTAssertEqual(state.permissionState, .accessible)
        XCTAssertEqual(state.placeholderState, .notPlaceholder)
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

    private func mobileLibraryRoute(path: String) -> MobileRepositoryConnectionRoute {
        .mobileLibrary(MobileRepositoryConnection(
            validation: .initialized(path: path),
            config: MobileRepositoryConfig(repoPath: path, defaultMode: "Copied", locale: "zh-Hans"),
            bookmark: bookmark(path: path)
        ))
    }

    private func candidate(path: String, validation: MobileRepositoryValidation) -> MobileRepositoryCandidate {
        MobileRepositoryCandidate(validation: validation, bookmark: bookmark(path: path))
    }

    private func bookmark(path: String) -> RepositoryBookmark {
        RepositoryBookmark(
            url: URL(fileURLWithPath: path),
            displayName: "Repository",
            pathDisplay: path,
            lastOpenedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
