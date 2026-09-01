@testable import AreaMatrixCoreBridgeContract
import AreaMatrixCoreContracts
import XCTest

final class CoreBridgeCapabilityContractTests: XCTestCase {
    func testCapabilityProtocolsCanBeImplementedWithoutGeneratedBindings() async throws {
        let implementation = ContractDouble()
        let report = try await implementation.inspectBindingContract(
            targetPlatform: .swift,
            bindingVersion: 1
        )
        let capabilities = try await implementation.getPlatformCapabilities(
            platform: .macos,
            appVersion: "test"
        )

        XCTAssertEqual(report.targetPlatform, .swift)
        XCTAssertEqual(report.bindingVersion, 1)
        XCTAssertEqual(capabilities.platform, .macos)
        XCTAssertEqual(capabilities.appVersion, "test")
    }
}

private struct ContractDouble: CoreBindingContractInspecting, CorePlatformCapabilitiesLoading {
    func inspectBindingContract(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64
    ) async throws -> BindingContractReportSnapshot {
        BindingContractReportSnapshot(
            targetPlatform: targetPlatform,
            bindingVersion: bindingVersion,
            coreVersion: "test",
            supportedApis: [],
            typeMappings: [],
            missingCapabilities: []
        )
    }

    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        .unknown(platform: platform, appVersion: appVersion, reason: "test")
    }
}
