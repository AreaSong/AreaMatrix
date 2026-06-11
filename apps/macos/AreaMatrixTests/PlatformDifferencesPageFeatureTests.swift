@testable import AreaMatrix
import XCTest

final class PlatformDifferencesPageFeatureTests: XCTestCase {
    @MainActor
    func testS4X02C401LoadsBindingContractThroughCoreBridgeBoundary() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .success(.fixture()))
        let capabilityLoader = PlatformDiffCapabilityLoader(result: .success(.fixture()))
        let model = PlatformDifferencesModel(
            appVersion: PlatformDifferencesModel.defaultTestAppVersion,
            selectedTargetPlatform: .swift,
            bindingVersion: 1,
            contractInspector: inspector,
            capabilityLoader: capabilityLoader,
            errorMapper: PlatformDifferencesStaticErrorMapper()
        )

        await model.load()
        let requests = await inspector.requests()
        let capabilityRequests = await capabilityLoader.requests()

        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.inspectBindingContract))
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.getPlatformCapabilities))
        XCTAssertEqual(requests, [PlatformDifferencesInspectRequest(
            targetPlatform: .swift,
            bindingVersion: 1
        )])
        XCTAssertEqual(capabilityRequests, [PlatformDifferencesCapabilityRequest(
            platform: .macos,
            appVersion: PlatformDifferencesModel.defaultTestAppVersion
        )])
        XCTAssertEqual(model.contractState, .loaded(.fixture()))
        XCTAssertEqual(model.capabilityState, .loaded(.fixture()))
    }

    @MainActor
    func testChangingTargetRechecksOnlyC401BindingContract() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .success(.fixture(targetPlatform: .kotlin)))
        let capabilityLoader = PlatformDiffCapabilityLoader(result: .success(.fixture()))
        let model = PlatformDifferencesModel(
            appVersion: PlatformDifferencesModel.defaultTestAppVersion,
            selectedTargetPlatform: .swift,
            bindingVersion: 1,
            contractInspector: inspector,
            capabilityLoader: capabilityLoader,
            errorMapper: PlatformDifferencesStaticErrorMapper()
        )

        model.selectTargetPlatform(.kotlin)
        await model.inspectContract()
        let requests = await inspector.requests()
        let capabilityRequests = await capabilityLoader.requests()

        XCTAssertEqual(model.selectedTargetPlatform, .kotlin)
        XCTAssertEqual(requests, [PlatformDifferencesInspectRequest(
            targetPlatform: .kotlin,
            bindingVersion: 1
        )])
        XCTAssertEqual(capabilityRequests, [])
    }

    @MainActor
    func testContractFailureUsesCoreErrorMapping() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .failure(CoreError.Config(reason: "bad version")))
        let capabilityLoader = PlatformDiffCapabilityLoader(result: .success(.fixture()))
        let model = PlatformDifferencesModel(
            appVersion: PlatformDifferencesModel.defaultTestAppVersion,
            contractInspector: inspector,
            capabilityLoader: capabilityLoader,
            errorMapper: PlatformDifferencesStaticErrorMapper()
        )

        await model.load()

        XCTAssertEqual(model.contractState, .failed(PlatformDifferencesContractError(
            message: "Binding contract unavailable",
            recovery: "Choose a supported binding version.",
            detail: "bad version"
        )))
        XCTAssertEqual(model.capabilityState, .loaded(.fixture()))
    }

    @MainActor
    func testCapabilityFailureFallsBackToUnknownRows() async {
        let capabilityLoader = PlatformDiffCapabilityLoader(
            result: .failure(CoreError.Config(reason: "platform Unknown"))
        )
        let model = PlatformDifferencesModel(
            appVersion: PlatformDifferencesModel.defaultTestAppVersion,
            contractInspector: PlatformDifferencesRecordingInspector(result: .success(.fixture())),
            capabilityLoader: capabilityLoader,
            errorMapper: PlatformDifferencesStaticErrorMapper()
        )

        await model.loadCapabilities()

        XCTAssertEqual(model.capabilityState, .failed(.unknown(
            platform: .macos,
            appVersion: PlatformDifferencesModel.defaultTestAppVersion,
            reason: "platform Unknown"
        ), PlatformDifferencesCapabilityError(
            message: "Capability snapshot unavailable",
            recovery: "Choose a supported binding version.",
            detail: "platform Unknown"
        )))
    }

    func testCapabilityRowsCoverS4X02PageSpecMatrix() {
        let rowNames = PlatformCapabilitiesSnapshot.fixture().pageSpecRows.map(\.name)

        XCTAssertEqual(rowNames, [
            "Repository access",
            "File import",
            "File watcher",
            "Cloud provider",
            "Trash / Recycle Bin",
            "Share integration",
            "Camera import"
        ])
        XCTAssertEqual(PlatformCapabilitiesSnapshot.fixture().pageSpecRows[1].support.status, .limited)
        XCTAssertTrue(
            PlatformCapabilitiesSnapshot
                .fixture()
                .pageSpecRows[1]
                .support
                .reason?
                .contains("preflight") == true
        )
    }
}

private struct PlatformDifferencesInspectRequest: Equatable {
    var targetPlatform: BindingTargetPlatformSnapshot
    var bindingVersion: Int64
}

private struct PlatformDifferencesCapabilityRequest: Equatable {
    var platform: PlatformIdSnapshot
    var appVersion: String
}

private actor PlatformDifferencesRecordingInspector: CoreBindingContractInspecting {
    private let result: Result<BindingContractReportSnapshot, Error>
    private var capturedRequests: [PlatformDifferencesInspectRequest] = []

    init(result: Result<BindingContractReportSnapshot, Error>) {
        self.result = result
    }

    func inspectBindingContract(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64
    ) async throws -> BindingContractReportSnapshot {
        capturedRequests.append(PlatformDifferencesInspectRequest(
            targetPlatform: targetPlatform,
            bindingVersion: bindingVersion
        ))
        return try result.get()
    }

    func requests() -> [PlatformDifferencesInspectRequest] {
        capturedRequests
    }
}

private actor PlatformDiffCapabilityLoader: CorePlatformCapabilitiesLoading {
    private let result: Result<PlatformCapabilitiesSnapshot, Error>
    private var capturedRequests: [PlatformDifferencesCapabilityRequest] = []

    init(result: Result<PlatformCapabilitiesSnapshot, Error>) {
        self.result = result
    }

    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        capturedRequests.append(PlatformDifferencesCapabilityRequest(
            platform: platform,
            appVersion: appVersion
        ))
        return try result.get()
    }

    func requests() -> [PlatformDifferencesCapabilityRequest] {
        capturedRequests
    }
}

private actor PlatformDifferencesStaticErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .config,
            userMessage: "Binding version is unsupported.",
            severity: .medium,
            suggestedAction: "Choose a supported binding version.",
            recoverability: .userActionRequired,
            rawContext: rawContext(for: error)
        )
    }

    private func rawContext(for error: CoreError) -> String {
        switch error {
        case let .Config(reason):
            reason
        default:
            error.localizedDescription
        }
    }
}

private extension PlatformDifferencesModel {
    static let defaultTestAppVersion = "1"
}

private extension BindingContractReportSnapshot {
    static func fixture(targetPlatform: BindingTargetPlatformSnapshot = .swift) -> BindingContractReportSnapshot {
        BindingContractReportSnapshot(
            targetPlatform: targetPlatform,
            bindingVersion: 1,
            coreVersion: "0.1.0",
            supportedApis: [
                BindingApiContractSnapshot(
                    name: "inspect_binding_contract",
                    capability: "C4-01",
                    status: .supported,
                    reason: nil
                )
            ],
            typeMappings: [
                BindingTypeMappingSnapshot(
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

private extension PlatformCapabilitiesSnapshot {
    static func fixture() -> PlatformCapabilitiesSnapshot {
        let available = PlatformCapabilitySupportSnapshot(
            status: .available,
            uiEnabled: true,
            requiresPermission: false,
            reason: nil
        )
        let limited = PlatformCapabilitySupportSnapshot(
            status: .limited,
            uiEnabled: false,
            requiresPermission: true,
            reason: "Requires platform permission."
        )
        return PlatformCapabilitiesSnapshot(
            platform: .macos,
            appVersion: PlatformDifferencesModel.defaultTestAppVersion,
            watcher: available,
            trash: available,
            shareExtension: limited,
            cloudPlaceholder: limited,
            securityBookmark: available
        )
    }
}
