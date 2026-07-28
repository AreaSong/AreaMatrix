@testable import AreaMatrix
import XCTest

private let platformDifferencesDefaultTestAppVersion = "1"

final class PlatformDifferencesPageFeatureTests: XCTestCase {
    @MainActor
    func testPlatformDifferencesCrossPlatformBindingContractCoreLoadsBindingContractThroughCoreBridgeBoundary() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .success(.fixture()))
        let capabilityLoader = PlatformDiffCapabilityLoader(result: .success(.fixture()))
        let model = makePlatformDifferencesModel(
            contractInspector: inspector,
            capabilityLoader: capabilityLoader
        )

        await model.load()

        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.inspectBindingContract))
        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.getPlatformCapabilities))
        await inspector.assertBindingContractInspectionRequests([PlatformDifferencesInspectRequest(
            targetPlatform: .swift,
            bindingVersion: 1
        )])
        await capabilityLoader.assertPlatformCapabilityRequests([PlatformDifferencesCapabilityRequest(
            platform: .macos,
            appVersion: platformDifferencesDefaultTestAppVersion
        )])
        XCTAssertEqual(model.contractState, .loaded(.fixture()))
        XCTAssertEqual(model.capabilityState, .loaded(.fixture()))
    }

    @MainActor
    func testChangingTargetRechecksOnlyCrossPlatformBindingContractCoreBindingContract() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .success(.fixture(targetPlatform: .kotlin)))
        let capabilityLoader = PlatformDiffCapabilityLoader(result: .success(.fixture()))
        let model = makePlatformDifferencesModel(
            contractInspector: inspector,
            capabilityLoader: capabilityLoader
        )

        model.selectTargetPlatform(.kotlin)
        await model.inspectContract()

        XCTAssertEqual(model.selectedTargetPlatform, .kotlin)
        await inspector.assertBindingContractInspectionRequests([PlatformDifferencesInspectRequest(
            targetPlatform: .kotlin,
            bindingVersion: 1
        )])
        await capabilityLoader.assertNoPlatformCapabilityRequests()
    }

    @MainActor
    func testContractFailureUsesCoreErrorMapping() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .failure(CoreError.Config(reason: "bad version")))
        let capabilityLoader = PlatformDiffCapabilityLoader(result: .success(.fixture()))
        let model = makePlatformDifferencesModel(
            contractInspector: inspector,
            capabilityLoader: capabilityLoader
        )

        await model.load()

        XCTAssertEqual(model.contractState, .failed(PlatformDifferencesContractError(
            message: L10n.message("Binding contract unavailable"),
            recovery: L10n.message(
                "error.unmapped.action",
                fallback: "Choose a supported binding version.",
                technicalDetail: "Choose a supported binding version."
            ),
            detail: "bad version"
        )))
        XCTAssertEqual(model.capabilityState, .loaded(.fixture()))
    }

    @MainActor
    func testCapabilityFailureFallsBackToUnknownRows() async {
        let capabilityLoader = PlatformDiffCapabilityLoader(
            result: .failure(CoreError.Config(reason: "platform Unknown"))
        )
        let model = makePlatformDifferencesModel(capabilityLoader: capabilityLoader)

        await model.loadCapabilities()

        XCTAssertEqual(model.capabilityState, .failed(.unknown(
            platform: .macos,
            appVersion: platformDifferencesDefaultTestAppVersion,
            reason: "platform Unknown"
        ), PlatformDifferencesCapabilityError(
            message: L10n.message("Capability snapshot unavailable"),
            recovery: L10n.message(
                "error.unmapped.action",
                fallback: "Choose a supported binding version.",
                technicalDetail: "Choose a supported binding version."
            ),
            detail: "platform Unknown"
        )))
    }

    @MainActor
    func testPlatformDifferencesUsesInjectedAppVersionReaderWhenNoOverrideIsPassed() async {
        let capabilityLoader = PlatformDiffCapabilityLoader(result: .success(.fixture()))
        let model = makePlatformDifferencesModel(
            appVersion: nil,
            appVersionReader: StaticAppVersionReader(version: "7.8.9 (10)"),
            contractInspector: PlatformDifferencesRecordingInspector(result: .success(.fixture())),
            capabilityLoader: capabilityLoader
        )

        await model.loadCapabilities()

        await capabilityLoader.assertPlatformCapabilityRequests([PlatformDifferencesCapabilityRequest(
            platform: .macos,
            appVersion: "7.8.9 (10)"
        )])
    }

    func testCapabilityRowsCoverPlatformDifferencesPageSpecMatrix() {
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

private typealias PlatformDifferencesCapabilityRequest = PlatformCapabilityRequest

private typealias PlatformDiffCapabilityLoader = RecordingPlatformCapabilityLoader

private typealias PlatformDifferencesStaticErrorMapper = RecordingCoreErrorMapper

@MainActor
private func makePlatformDifferencesModel(
    appVersion: String? = platformDifferencesDefaultTestAppVersion,
    appVersionReader: any AppVersionReading = StaticAppVersionReader(
        version: platformDifferencesDefaultTestAppVersion
    ),
    selectedTargetPlatform: BindingTargetPlatformSnapshot = .swift,
    bindingVersion: Int64 = 1,
    contractInspector: any CoreBindingContractInspecting = PlatformDifferencesRecordingInspector(
        result: .success(.fixture())
    ),
    capabilityLoader: any CorePlatformCapabilitiesLoading = PlatformDiffCapabilityLoader(result: .success(.fixture())),
    errorMapper: any CoreErrorMapping = platformDifferencesStaticErrorMapper()
) -> PlatformDifferencesModel {
    PlatformDifferencesModel(
        appVersion: appVersion,
        appVersionReader: appVersionReader,
        selectedTargetPlatform: selectedTargetPlatform,
        bindingVersion: bindingVersion,
        contractInspector: contractInspector,
        capabilityLoader: capabilityLoader,
        errorMapper: errorMapper
    )
}

private func platformDifferencesStaticErrorMapper() -> PlatformDifferencesStaticErrorMapper {
    RecordingCoreErrorMapper { error in
        CoreErrorMappingSnapshot.testFixture(
            kind: .config,
            userMessage: "Binding version is unsupported.",
            severity: .medium,
            suggestedAction: "Choose a supported binding version.",
            recoverability: .userActionRequired,
            rawContext: platformDifferencesRawContext(for: error)
        )
    }
}

private func platformDifferencesRawContext(for error: CoreError) -> String {
    switch error {
    case let .Config(reason):
        reason
    default:
        error.localizedDescription
    }
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
                    capability: "binding-contract",
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
        let available = PlatformCapabilitySupportSnapshot.testFixture()
        let limited = PlatformCapabilitySupportSnapshot.limitedFixture()
        return PlatformCapabilitiesSnapshot.testFixture(
            appVersion: platformDifferencesDefaultTestAppVersion,
            watcher: available,
            trash: available,
            shareExtension: limited,
            cloudPlaceholder: limited,
            securityBookmark: available
        )
    }
}
