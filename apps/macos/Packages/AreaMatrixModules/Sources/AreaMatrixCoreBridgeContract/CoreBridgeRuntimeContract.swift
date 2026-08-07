/// Runtime-facing contract shared by the App composition root and future
/// CoreBridge adapters.
///
/// The implementation remains App-owned while it depends on generated
/// UniFFI bindings. Keeping the capability surface here makes that ownership
/// explicit and lets consumers depend on a stable contract during migration.
public enum CoreBridgeRuntimeState: String, Equatable, Sendable {
    case unavailable
    case generatedBindings
}

public enum CoreBridgeRuntimeError: Error, Equatable, Sendable {
    case undeclaredBoundary(CoreBridgeBoundary)
}

public protocol CoreBridgeRuntimeProviding: Sendable {
    var state: CoreBridgeRuntimeState { get }
    func coreAvailability() -> String
    func declaredBoundaries() async -> [CoreBridgeBoundary]
    func isDeclared(_ boundary: CoreBridgeBoundary) -> Bool
}
