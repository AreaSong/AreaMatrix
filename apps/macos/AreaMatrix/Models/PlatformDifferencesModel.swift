import Combine
import Foundation

enum PlatformDifferencesContractState: Equatable {
    case loading
    case loaded(BindingContractReportSnapshot)
    case failed(PlatformDifferencesContractError)
}

struct PlatformDifferencesContractError: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

@MainActor
final class PlatformDifferencesModel: ObservableObject {
    @Published private(set) var contractState: PlatformDifferencesContractState = .loading
    @Published private(set) var isInspectingContract = false
    @Published private(set) var selectedTargetPlatform: BindingTargetPlatformSnapshot

    let bindingVersion: Int64
    private let contractInspector: any CoreBindingContractInspecting
    private let errorMapper: any CoreErrorMapping

    init(
        selectedTargetPlatform: BindingTargetPlatformSnapshot = .swift,
        bindingVersion: Int64 = 1,
        contractInspector: any CoreBindingContractInspecting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.selectedTargetPlatform = selectedTargetPlatform
        self.bindingVersion = bindingVersion
        self.contractInspector = contractInspector
        self.errorMapper = errorMapper
    }

    var contractActionTitle: String {
        isInspectingContract ? "Checking contract..." : "Check contract"
    }

    func load() async {
        await inspectContract()
    }

    func selectTargetPlatform(_ targetPlatform: BindingTargetPlatformSnapshot) {
        selectedTargetPlatform = targetPlatform
    }

    func inspectContract() async {
        isInspectingContract = true
        contractState = .loading
        defer {
            isInspectingContract = false
        }

        do {
            let report = try await contractInspector.inspectBindingContract(
                targetPlatform: selectedTargetPlatform,
                bindingVersion: bindingVersion
            )
            contractState = .loaded(report)
        } catch {
            contractState = .failed(await contractError(for: error))
        }
    }

    private func contractError(for error: Error) async -> PlatformDifferencesContractError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return PlatformDifferencesContractError(
                message: "Binding contract unavailable",
                recovery: mapping.suggestedAction.isEmpty ? mapping.userMessage : mapping.suggestedAction,
                detail: mapping.rawContext.isEmpty ? coreError.localizedDescription : mapping.rawContext
            )
        }

        if let bridgeError = error as? CoreBridgeError {
            return PlatformDifferencesContractError(
                message: "Binding contract unavailable",
                recovery: "Check the Core bridge integration, then retry.",
                detail: bridgeError.localizedDescription
            )
        }

        return PlatformDifferencesContractError(
            message: "Binding contract unavailable",
            recovery: "Retry the contract check.",
            detail: error.localizedDescription
        )
    }
}
