@testable import AreaMatrix
import XCTest

final class PlatformDifferencesPageFeatureTests: XCTestCase {
    @MainActor
    func testS4X02C401LoadsBindingContractThroughCoreBridgeBoundary() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .success(.fixture()))
        let model = PlatformDifferencesModel(
            selectedTargetPlatform: .swift,
            bindingVersion: 1,
            contractInspector: inspector,
            errorMapper: PlatformDifferencesStaticErrorMapper()
        )

        await model.load()
        let requests = await inspector.requests()

        XCTAssertTrue(CoreBridgeBoundary.allCases.contains(.inspectBindingContract))
        XCTAssertEqual(requests, [PlatformDifferencesInspectRequest(
            targetPlatform: .swift,
            bindingVersion: 1
        )])
        XCTAssertEqual(model.contractState, .loaded(.fixture()))
    }

    @MainActor
    func testChangingTargetRechecksOnlyC401BindingContract() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .success(.fixture(targetPlatform: .kotlin)))
        let model = PlatformDifferencesModel(
            selectedTargetPlatform: .swift,
            bindingVersion: 1,
            contractInspector: inspector,
            errorMapper: PlatformDifferencesStaticErrorMapper()
        )

        model.selectTargetPlatform(.kotlin)
        await model.inspectContract()
        let requests = await inspector.requests()

        XCTAssertEqual(model.selectedTargetPlatform, .kotlin)
        XCTAssertEqual(requests, [PlatformDifferencesInspectRequest(
            targetPlatform: .kotlin,
            bindingVersion: 1
        )])
    }

    @MainActor
    func testContractFailureUsesCoreErrorMapping() async {
        let inspector = PlatformDifferencesRecordingInspector(result: .failure(CoreError.Config(reason: "bad version")))
        let model = PlatformDifferencesModel(
            contractInspector: inspector,
            errorMapper: PlatformDifferencesStaticErrorMapper()
        )

        await model.load()

        XCTAssertEqual(model.contractState, .failed(PlatformDifferencesContractError(
            message: "Binding contract unavailable",
            recovery: "Choose a supported binding version.",
            detail: "bad version"
        )))
    }
}

private struct PlatformDifferencesInspectRequest: Equatable, Sendable {
    var targetPlatform: BindingTargetPlatformSnapshot
    var bindingVersion: Int64
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
