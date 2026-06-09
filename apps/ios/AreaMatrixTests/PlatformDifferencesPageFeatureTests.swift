@testable import AreaMatrixIOS
import XCTest

@MainActor
final class PlatformDifferencesPageFeatureTests: XCTestCase {
    func testIOSPlatformDifferencesLoadsC401BindingContract() async {
        let inspector = RecordingPlatformDifferencesInspector(report: .fixture(targetPlatform: .swift))
        let model = PlatformDifferencesViewModel(
            hostPlatform: "iOS",
            selectedTargetPlatform: .swift,
            bindingVersion: 1,
            inspector: inspector
        )

        await model.load()

        XCTAssertEqual(model.hostPlatform, "iOS")
        XCTAssertEqual(model.contractState, .loaded(.fixture(targetPlatform: .swift)))
        let requests = await inspector.recordedRequests()
        XCTAssertEqual(requests, [BindingContractRequestRecord(
            targetPlatform: .swift,
            bindingVersion: 1
        )])
    }

    func testChangingBindingTargetRechecksOnlyC401Contract() async {
        let inspector = RecordingPlatformDifferencesInspector(report: .fixture(targetPlatform: .python))
        let model = PlatformDifferencesViewModel(
            selectedTargetPlatform: .swift,
            inspector: inspector
        )

        model.selectTargetPlatform(.python)
        await model.inspectContract()

        XCTAssertEqual(model.selectedTargetPlatform, .python)
        let requests = await inspector.recordedRequests()
        XCTAssertEqual(requests, [BindingContractRequestRecord(
            targetPlatform: .python,
            bindingVersion: 1
        )])
    }

    func testContractFailureMapsToVisibleRecovery() async {
        let inspector = RecordingPlatformDifferencesInspector(
            error: PlatformDifferencesBindingContractError.config("unsupported version")
        )
        let model = PlatformDifferencesViewModel(inspector: inspector)

        await model.load()

        let expectedState = PlatformDifferencesContractState.failed(PlatformDifferencesContractFailure(
            message: "Binding contract unavailable",
            recovery: "Choose a supported binding contract version, then retry.",
            detail: "unsupported version"
        ))
        XCTAssertEqual(model.contractState, expectedState)
    }
}

private struct BindingContractRequestRecord: Equatable, Sendable {
    var targetPlatform: PlatformDifferencesBindingTarget
    var bindingVersion: Int64
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
