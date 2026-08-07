import Foundation

@MainActor
extension ObservabilityRuntimeAssembly {
    static let shared = ObservabilityRuntimeAssembly(
        hub: .shared,
        core: AppCoreServices.observabilityController,
        resourceIdentityProvider: .shared,
        sessionID: ObservabilityProcessIdentity.sessionID,
        scheduler: .live
    )
}
