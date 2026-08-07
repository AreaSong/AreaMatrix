@testable import AreaMatrixCoreContracts
import XCTest

final class BindingContractSnapshotTests: XCTestCase {
    func testBindingContractValuesPreserveStableWireValues() {
        XCTAssertEqual(BindingTargetPlatformSnapshot.swift.rawValue, "Swift")
        XCTAssertEqual(BindingTargetPlatformSnapshot.allCases, [.swift, .kotlin, .python])
        XCTAssertEqual(BindingSupportStatusSnapshot.missing.rawValue, "Missing")
    }

    func testBindingContractSnapshotsExposeStableIdentity() {
        let api = BindingApiContractSnapshot(
            name: "inspect_binding_contract",
            capability: "binding-contract",
            status: .supported,
            reason: nil
        )
        let mapping = BindingTypeMappingSnapshot(
            rustType: "RepositoryId",
            udlType: "string",
            targetType: "String",
            status: .supported,
            reason: nil
        )
        let missing = BindingMissingCapabilitySnapshot(
            capability: "camera",
            label: "Camera import",
            status: .limited,
            reason: "Permission is required."
        )

        XCTAssertEqual(api.id, "binding-contract-inspect_binding_contract")
        XCTAssertEqual(mapping.id, "RepositoryId-string-String")
        XCTAssertEqual(missing.id, "camera-Camera import")
    }

    func testBindingContractReportIsValueStableAndSendable() {
        let report = BindingContractReportSnapshot(
            targetPlatform: .swift,
            bindingVersion: 3,
            coreVersion: "0.1.0",
            supportedApis: [],
            typeMappings: [],
            missingCapabilities: []
        )

        XCTAssertEqual(report, report)
        XCTAssertEqual(report.bindingVersion, 3)
        XCTAssertEqual(report.coreVersion, "0.1.0")
    }
}
