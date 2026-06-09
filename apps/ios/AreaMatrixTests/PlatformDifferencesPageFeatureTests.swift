@testable import AreaMatrixIOS
import XCTest

@MainActor
final class PlatformDifferencesPageFeatureTests: XCTestCase {
    func testIOSPlatformDifferencesLoadsC401BindingContract() async {
        let inspector = RecordingPlatformDifferencesInspector(report: .fixture(targetPlatform: .swift))
        let capabilities = RecordingPlatformDifferencesCapabilityLoader(capabilities: .iosFixture())
        let model = PlatformDifferencesViewModel(
            hostPlatform: .ios,
            appVersion: "1.2.3",
            selectedTargetPlatform: .swift,
            bindingVersion: 1,
            inspector: inspector,
            capabilityLoader: capabilities
        )

        await model.load()

        XCTAssertEqual(model.hostPlatform, .ios)
        XCTAssertEqual(model.contractState, .loaded(.fixture(targetPlatform: .swift)))
        XCTAssertEqual(model.capabilityState, .loaded(.iosFixture()))
        let requests = await inspector.recordedRequests()
        XCTAssertEqual(requests, [BindingContractRequestRecord(
            targetPlatform: .swift,
            bindingVersion: 1
        )])
        let capabilityRequests = await capabilities.recordedRequests()
        XCTAssertEqual(capabilityRequests, [CapabilityRequestRecord(platform: .ios, appVersion: "1.2.3")])
    }

    func testChangingBindingTargetRechecksOnlyC401Contract() async {
        let inspector = RecordingPlatformDifferencesInspector(report: .fixture(targetPlatform: .python))
        let capabilities = RecordingPlatformDifferencesCapabilityLoader(capabilities: .iosFixture())
        let model = PlatformDifferencesViewModel(
            selectedTargetPlatform: .swift,
            inspector: inspector,
            capabilityLoader: capabilities
        )

        model.selectTargetPlatform(.python)
        await model.inspectContract()

        XCTAssertEqual(model.selectedTargetPlatform, .python)
        let requests = await inspector.recordedRequests()
        XCTAssertEqual(requests, [BindingContractRequestRecord(
            targetPlatform: .python,
            bindingVersion: 1
        )])
        let capabilityRequests = await capabilities.recordedRequests()
        XCTAssertEqual(capabilityRequests, [])
    }

    func testContractFailureMapsToVisibleRecovery() async {
        let inspector = RecordingPlatformDifferencesInspector(
            error: PlatformDifferencesBindingContractError.config("unsupported version")
        )
        let capabilities = RecordingPlatformDifferencesCapabilityLoader(capabilities: .iosFixture())
        let model = PlatformDifferencesViewModel(inspector: inspector, capabilityLoader: capabilities)

        await model.load()

        let expectedState = PlatformDifferencesContractState.failed(PlatformDifferencesContractFailure(
            message: "Binding contract unavailable",
            recovery: "Choose a supported binding contract version, then retry.",
            detail: "unsupported version"
        ))
        XCTAssertEqual(model.contractState, expectedState)
        XCTAssertEqual(model.capabilityState, .loaded(.iosFixture()))
    }

    func testCapabilityFailureMapsRowsToUnknownWithoutStaticAvailability() async {
        let inspector = RecordingPlatformDifferencesInspector(report: .fixture(targetPlatform: .swift))
        let capabilities = RecordingPlatformDifferencesCapabilityLoader(
            error: PlatformDifferencesCapabilityError.config("platform Unknown")
        )
        let model = PlatformDifferencesViewModel(inspector: inspector, capabilityLoader: capabilities)

        await model.loadCapabilities()

        let expectedState = PlatformDifferencesCapabilityState.failed(PlatformDifferencesCapabilityFailure(
            message: "Capability snapshot unavailable",
            recovery: "Use a supported platform id and app version, then retry.",
            detail: "platform Unknown"
        ))
        XCTAssertEqual(model.capabilityState, expectedState)
    }

    func testIOSCapabilityRowsCoverS4X02PageSpecMatrix() {
        let rowNames = PlatformDifferencesCapabilities.iosFixture().pageSpecRows.map(\.name)

        XCTAssertEqual(rowNames, [
            "Repository access",
            "File import",
            "File watcher",
            "Cloud provider",
            "Trash / Recycle Bin",
            "Share integration",
            "Camera import"
        ])
        XCTAssertEqual(PlatformDifferencesCapabilities.iosFixture().pageSpecRows[6].support.status, .limited)
        XCTAssertTrue(
            PlatformDifferencesCapabilities
                .iosFixture()
                .pageSpecRows[6]
                .support
                .reason?
                .contains("camera import flow") == true
        )
    }

    func testIOSPlatformDifferencesIsReachableFromConnectRepositoryHelp() throws {
        let appSource = try Self.readSource("../AreaMatrixApp/AreaMatrixIOSApp.swift")
        let connectSource = try Self.readSource("../AreaMatrix/Features/Onboarding/ConnectRepositoryView.swift")
        let routeSource = try Self.readSource(
            "../AreaMatrix/Features/Onboarding/ConnectRepositoryRouteDestinationView.swift"
        )
        let helpSource = try Self.readSource("../AreaMatrix/Features/Help/PlatformDifferencesView.swift")

        XCTAssertTrue(appSource.contains("ConnectRepositoryEntryView()"))
        XCTAssertTrue(connectSource.contains("Button(\"Help\")"))
        XCTAssertTrue(connectSource.contains(".sheet(isPresented: $showingRepositoryHelp)"))
        XCTAssertTrue(connectSource.contains("ConnectRepositoryHelpView()"))
        XCTAssertTrue(routeSource.contains("NavigationLink"))
        XCTAssertTrue(routeSource.contains("PlatformDifferencesView()"))
        XCTAssertTrue(routeSource.contains("Platform capabilities"))
        XCTAssertTrue(helpSource.contains("Open repository settings"))
        XCTAssertTrue(helpSource.contains("Export diagnostics"))
        XCTAssertTrue(helpSource.contains("Close"))
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

private struct BindingContractRequestRecord: Equatable, Sendable {
    var targetPlatform: PlatformDifferencesBindingTarget
    var bindingVersion: Int64
}

private struct CapabilityRequestRecord: Equatable, Sendable {
    var platform: PlatformDifferencesPlatformId
    var appVersion: String
}

private actor RecordingPlatformDifferencesInspector: PlatformDifferencesBindingContractInspecting {
    private let result: Result<PlatformDifferencesBindingContractReport, Error>
    private var capturedRequests: [BindingContractRequestRecord] = []

    init(report: PlatformDifferencesBindingContractReport) {
        result = .success(report)
    }

    init(error: Error) {
        result = .failure(error)
    }

    func recordedRequests() -> [BindingContractRequestRecord] {
        capturedRequests
    }

    func inspectBindingContract(
        targetPlatform: PlatformDifferencesBindingTarget,
        bindingVersion: Int64
    ) async throws -> PlatformDifferencesBindingContractReport {
        capturedRequests.append(BindingContractRequestRecord(
            targetPlatform: targetPlatform,
            bindingVersion: bindingVersion
        ))
        return try result.get()
    }
}

private actor RecordingPlatformDifferencesCapabilityLoader: PlatformDifferencesCapabilityLoading {
    private let result: Result<PlatformDifferencesCapabilities, Error>
    private var capturedRequests: [CapabilityRequestRecord] = []

    init(capabilities: PlatformDifferencesCapabilities) {
        result = .success(capabilities)
    }

    init(error: Error) {
        result = .failure(error)
    }

    func recordedRequests() -> [CapabilityRequestRecord] {
        capturedRequests
    }

    func getPlatformCapabilities(
        platform: PlatformDifferencesPlatformId,
        appVersion: String
    ) async throws -> PlatformDifferencesCapabilities {
        capturedRequests.append(CapabilityRequestRecord(platform: platform, appVersion: appVersion))
        return try result.get()
    }
}

private extension PlatformDifferencesBindingContractReport {
    static func fixture(targetPlatform: PlatformDifferencesBindingTarget) -> PlatformDifferencesBindingContractReport {
        PlatformDifferencesBindingContractReport(
            targetPlatform: targetPlatform,
            bindingVersion: 1,
            coreVersion: "0.1.0",
            supportedApis: [
                PlatformDifferencesBindingApiContract(
                    name: "inspect_binding_contract",
                    capability: "C4-01",
                    status: .supported,
                    reason: nil
                )
            ],
            typeMappings: [
                PlatformDifferencesBindingTypeMapping(
                    rustType: "BindingContractReport",
                    udlType: "dictionary BindingContractReport",
                    targetType: "\(targetPlatform.rawValue) BindingContractReport",
                    status: .supported,
                    reason: nil
                )
            ],
            missingCapabilities: []
        )
    }
}

private extension PlatformDifferencesCapabilities {
    static func iosFixture() -> PlatformDifferencesCapabilities {
        PlatformDifferencesCapabilities(
            platform: .ios,
            appVersion: "1.2.3",
            watcher: PlatformDifferencesCapabilitySupport(
                status: .limited,
                uiEnabled: false,
                requiresPermission: true,
                reason: "iOS background access is sandbox-limited."
            ),
            trash: PlatformDifferencesCapabilitySupport(
                status: .notAvailable,
                uiEnabled: false,
                requiresPermission: false,
                reason: "iOS does not expose an AreaMatrix-managed Trash equivalent."
            ),
            shareExtension: PlatformDifferencesCapabilitySupport(
                status: .available,
                uiEnabled: true,
                requiresPermission: true,
                reason: nil
            ),
            cloudPlaceholder: PlatformDifferencesCapabilitySupport(
                status: .limited,
                uiEnabled: false,
                requiresPermission: true,
                reason: "iCloud placeholders require platform preflight."
            ),
            securityBookmark: PlatformDifferencesCapabilitySupport(
                status: .available,
                uiEnabled: true,
                requiresPermission: true,
                reason: nil
            )
        )
    }
}
