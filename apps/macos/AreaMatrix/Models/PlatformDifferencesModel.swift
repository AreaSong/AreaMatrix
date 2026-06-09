import Combine
import Foundation

enum PlatformDifferencesContractState: Equatable {
    case loading
    case loaded(BindingContractReportSnapshot)
    case failed(PlatformDifferencesContractError)
}

enum PlatformDifferencesCapabilityState: Equatable {
    case loading
    case loaded(PlatformCapabilitiesSnapshot)
    case failed(PlatformCapabilitiesSnapshot, PlatformDifferencesCapabilityError)
}

struct PlatformDifferencesContractError: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

struct PlatformDifferencesCapabilityError: Equatable {
    var message: String
    var recovery: String
    var detail: String
}

@MainActor
final class PlatformDifferencesModel: ObservableObject {
    @Published private(set) var contractState: PlatformDifferencesContractState = .loading
    @Published private(set) var capabilityState: PlatformDifferencesCapabilityState = .loading
    @Published private(set) var isInspectingContract = false
    @Published private(set) var isLoadingCapabilities = false
    @Published private(set) var selectedTargetPlatform: BindingTargetPlatformSnapshot

    let hostPlatform: PlatformIdSnapshot
    let appVersion: String
    let repositoryText: String
    let bindingVersion: Int64
    private let contractInspector: any CoreBindingContractInspecting
    private let capabilityLoader: any CorePlatformCapabilitiesLoading
    private let errorMapper: any CoreErrorMapping

    init(
        hostPlatform: PlatformIdSnapshot = .macos,
        appVersion: String = PlatformDifferencesModel.defaultAppVersion(),
        repositoryText: String = "Not connected",
        selectedTargetPlatform: BindingTargetPlatformSnapshot = .swift,
        bindingVersion: Int64 = 1,
        contractInspector: any CoreBindingContractInspecting = CoreBridge(),
        capabilityLoader: any CorePlatformCapabilitiesLoading = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.hostPlatform = hostPlatform
        self.appVersion = appVersion
        self.repositoryText = repositoryText
        self.selectedTargetPlatform = selectedTargetPlatform
        self.bindingVersion = bindingVersion
        self.contractInspector = contractInspector
        self.capabilityLoader = capabilityLoader
        self.errorMapper = errorMapper
    }

    var contractActionTitle: String {
        isInspectingContract ? "Checking contract..." : "Check contract"
    }

    func load() async {
        await loadCapabilities()
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

    func loadCapabilities() async {
        isLoadingCapabilities = true
        capabilityState = .loading
        defer {
            isLoadingCapabilities = false
        }

        do {
            let capabilities = try await capabilityLoader.getPlatformCapabilities(
                platform: hostPlatform,
                appVersion: appVersion
            )
            capabilityState = .loaded(capabilities)
        } catch {
            let mappedError = await capabilityError(for: error)
            capabilityState = .failed(.unknown(
                platform: hostPlatform,
                appVersion: appVersion,
                reason: mappedError.detail
            ), mappedError)
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

    private func capabilityError(for error: Error) async -> PlatformDifferencesCapabilityError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return PlatformDifferencesCapabilityError(
                message: "Capability snapshot unavailable",
                recovery: mapping.suggestedAction.isEmpty ? mapping.userMessage : mapping.suggestedAction,
                detail: mapping.rawContext.isEmpty ? coreError.localizedDescription : mapping.rawContext
            )
        }

        if let bridgeError = error as? CoreBridgeError {
            return PlatformDifferencesCapabilityError(
                message: "Capability snapshot unavailable",
                recovery: "Check the Core platform capability bridge, then retry.",
                detail: bridgeError.localizedDescription
            )
        }

        return PlatformDifferencesCapabilityError(
            message: "Capability snapshot unavailable",
            recovery: "Retry the platform capability check.",
            detail: error.localizedDescription
        )
    }

    private nonisolated static func defaultAppVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
    }
}
