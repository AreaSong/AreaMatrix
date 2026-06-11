@testable import AreaMatrixIOS
import XCTest

final class RepositorySettingsPageIntegrationTests: XCTestCase {
    @MainActor
    func testS4X08LoadsRepositoryConfigCapabilitiesAndCoreVersion() async {
        let bridge = FakeMobileRepositoryCoreBridge(validation: .initialized(path: "/tmp/AreaMatrixRepo"))
        let capabilityLoader = RecordingRepositorySettingsCapabilityLoader(capabilities: .repositorySettingsFixture())
        let model = RepositorySettingsViewModel(
            repoPath: "/tmp/AreaMatrixRepo",
            bridge: bridge,
            capabilityLoader: capabilityLoader
        )

        await model.load()

        let requests = await capabilityLoader.recordedRequests()
        guard case let .loaded(snapshot) = model.state else {
            XCTFail("Expected loaded repository settings state.")
            return
        }

        XCTAssertEqual(bridge.loadedConfigPaths, ["/tmp/AreaMatrixRepo"])
        XCTAssertEqual(requests, [RepositorySettingsCapabilityRequest(platform: .ios, appVersion: "1")])
        XCTAssertEqual(snapshot.name, "AreaMatrixRepo")
        XCTAssertEqual(snapshot.location, "/tmp/AreaMatrixRepo")
        XCTAssertEqual(snapshot.locationType, "Local folder")
        XCTAssertEqual(snapshot.coreVersion, "test-core")
        XCTAssertEqual(snapshot.access, "Available")
        XCTAssertEqual(snapshot.watcher, "Available")
        XCTAssertTrue(model.canExportDiagnostics)
    }

    @MainActor
    func testS4X08SavesRepositoryConfigThroughUpdateConfig() async {
        let bridge = FakeMobileRepositoryCoreBridge(validation: .initialized(path: "/tmp/AreaMatrixRepo"))
        let model = RepositorySettingsViewModel(
            repoPath: "/tmp/AreaMatrixRepo",
            bridge: bridge,
            capabilityLoader: RecordingRepositorySettingsCapabilityLoader(capabilities: .repositorySettingsFixture())
        )

        await model.load()
        await model.saveFallbackToInbox(false)

        XCTAssertEqual(bridge.updatedConfigRequests.count, 1)
        XCTAssertEqual(bridge.updatedConfigRequests.first?.repoPath, "/tmp/AreaMatrixRepo")
        XCTAssertEqual(bridge.updatedConfigRequests.first?.config.repoPath, "/tmp/AreaMatrixRepo")
        XCTAssertEqual(bridge.updatedConfigRequests.first?.config.fallbackToInbox, false)
        XCTAssertEqual(bridge.loadedConfigPaths, ["/tmp/AreaMatrixRepo", "/tmp/AreaMatrixRepo"])
    }

    @MainActor
    func testS4X08ExportsRedactedDiagnosticsFromLoadedSnapshot() async {
        let bridge = FakeMobileRepositoryCoreBridge(validation: .initialized(path: "/tmp/AreaMatrixRepo"))
        let exporter = RecordingRepositorySettingsDiagnosticsExporter(outputPath: "/tmp/diag.txt")
        let model = RepositorySettingsViewModel(
            repoPath: "/tmp/AreaMatrixRepo",
            bridge: bridge,
            capabilityLoader: RecordingRepositorySettingsCapabilityLoader(capabilities: .repositorySettingsFixture()),
            diagnosticsExporter: exporter
        )

        await model.load()
        await model.exportDiagnostics()

        let snapshots = await exporter.recordedSnapshots()
        XCTAssertEqual(snapshots.map(\.location), ["/tmp/AreaMatrixRepo"])
        XCTAssertEqual(model.diagnosticsState, .exported("/tmp/diag.txt"))
        XCTAssertTrue(model.canExportDiagnostics)
    }

    @MainActor
    func testS4X08ShowsNoRepositoryConnectedEmptyState() async {
        let model = RepositorySettingsViewModel(
            repoPath: nil,
            bridge: FakeMobileRepositoryCoreBridge(validation: .initialized(path: "/tmp/unused")),
            capabilityLoader: RecordingRepositorySettingsCapabilityLoader(capabilities: .repositorySettingsFixture())
        )

        await model.load()

        XCTAssertEqual(model.state, .empty)
        XCTAssertFalse(model.canExportDiagnostics)
    }
}

private struct RepositorySettingsCapabilityRequest: Equatable {
    var platform: PlatformDifferencesPlatformId
    var appVersion: String
}

private actor RecordingRepositorySettingsCapabilityLoader: PlatformDifferencesCapabilityLoading {
    private let result: Result<PlatformDifferencesCapabilities, Error>
    private var requests: [RepositorySettingsCapabilityRequest] = []

    init(capabilities: PlatformDifferencesCapabilities) {
        result = .success(capabilities)
    }

    func recordedRequests() -> [RepositorySettingsCapabilityRequest] {
        requests
    }

    func getPlatformCapabilities(
        platform: PlatformDifferencesPlatformId,
        appVersion: String
    ) async throws -> PlatformDifferencesCapabilities {
        requests.append(RepositorySettingsCapabilityRequest(platform: platform, appVersion: appVersion))
        return try result.get()
    }
}

private actor RecordingRepositorySettingsDiagnosticsExporter: RepositorySettingsDiagnosticsExporting {
    private let outputPath: String
    private var snapshots: [RepositorySettingsSnapshot] = []

    init(outputPath: String) {
        self.outputPath = outputPath
    }

    func recordedSnapshots() -> [RepositorySettingsSnapshot] {
        snapshots
    }

    func export(snapshot: RepositorySettingsSnapshot) async throws -> String {
        snapshots.append(snapshot)
        return outputPath
    }
}

private extension PlatformDifferencesCapabilities {
    static func repositorySettingsFixture() -> PlatformDifferencesCapabilities {
        let available = PlatformDifferencesCapabilitySupport(
            status: .available,
            uiEnabled: true,
            requiresPermission: false,
            reason: nil
        )
        let unavailable = PlatformDifferencesCapabilitySupport(
            status: .notAvailable,
            uiEnabled: false,
            requiresPermission: false,
            reason: nil
        )
        return PlatformDifferencesCapabilities(
            platform: .ios,
            appVersion: "1",
            watcher: available,
            trash: available,
            shareExtension: available,
            cloudPlaceholder: unavailable,
            securityBookmark: available
        )
    }
}
