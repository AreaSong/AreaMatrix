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
    var message: LocalizedMessage
    var recovery: LocalizedMessage
    var detail: String
}

struct PlatformDifferencesCapabilityError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
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
    private let repositoryTextValue: String?
    let bindingVersion: Int64
    private let contractInspector: any CoreBindingContractInspecting
    private let capabilityLoader: any CorePlatformCapabilitiesLoading
    private let errorMapper: any CoreErrorMapping

    init(
        hostPlatform: PlatformIdSnapshot = .macos,
        appVersion: String? = nil,
        appVersionReader: any AppVersionReading = PlatformDifferencesPlatformServices.appVersionReader,
        repositoryText: String? = nil,
        selectedTargetPlatform: BindingTargetPlatformSnapshot = .swift,
        bindingVersion: Int64 = 1,
        contractInspector: any CoreBindingContractInspecting = AppCoreServices.bindingContractInspector,
        capabilityLoader: any CorePlatformCapabilitiesLoading = AppCoreServices.platformCapabilityLoader,
        errorMapper: any CoreErrorMapping = AppCoreServices.errorMapper
    ) {
        self.hostPlatform = hostPlatform
        self.appVersion = appVersion ?? appVersionReader.appVersion()
        repositoryTextValue = repositoryText
        self.selectedTargetPlatform = selectedTargetPlatform
        self.bindingVersion = bindingVersion
        self.contractInspector = contractInspector
        self.capabilityLoader = capabilityLoader
        self.errorMapper = errorMapper
    }

    var repositoryText: String {
        repositoryTextValue ?? L10n.string("Not connected")
    }

    var contractActionTitle: String {
        isInspectingContract ? L10n.string("Checking contract...") : L10n.string("Check contract")
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
            contractState = await .failed(contractError(for: error))
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
        if let display = await errorMapper.mapCoreErrorDisplayIfPresent(error) {
            return PlatformDifferencesContractError(
                message: L10n.message("Binding contract unavailable"),
                recovery: display.recovery,
                detail: display.detail
            )
        }

        if let bridgeError = error as? CoreBridgeError {
            return PlatformDifferencesContractError(
                message: L10n.message("Binding contract unavailable"),
                recovery: L10n.message("Check the Core bridge integration, then retry."),
                detail: bridgeError.localizedDescription
            )
        }

        return PlatformDifferencesContractError(
            message: L10n.message("Binding contract unavailable"),
            recovery: L10n.message("Retry the contract check."),
            detail: error.localizedDescription
        )
    }

    private func capabilityError(for error: Error) async -> PlatformDifferencesCapabilityError {
        if let display = await errorMapper.mapCoreErrorDisplayIfPresent(error) {
            return PlatformDifferencesCapabilityError(
                message: L10n.message("Capability snapshot unavailable"),
                recovery: display.recovery,
                detail: display.detail
            )
        }

        if let bridgeError = error as? CoreBridgeError {
            return PlatformDifferencesCapabilityError(
                message: L10n.message("Capability snapshot unavailable"),
                recovery: L10n.message("Check the Core platform capability bridge, then retry."),
                detail: bridgeError.localizedDescription
            )
        }

        return PlatformDifferencesCapabilityError(
            message: L10n.message("Capability snapshot unavailable"),
            recovery: L10n.message("Retry the platform capability check."),
            detail: error.localizedDescription
        )
    }
}
