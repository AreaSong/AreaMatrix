import AreaMatrixCoreBridgeContract

/// Owns the stable, platform-neutral runtime metadata for a CoreBridge.
///
/// Generated UniFFI calls and App-owned snapshot conversion stay in the App
/// adapter. This coordinator keeps runtime state and boundary inventory in a
/// reusable package so feature composition does not depend on that adapter's
/// implementation details.
public actor CoreBridgeRuntimeCoordinator: CoreBridgeRuntimeProviding {
    public nonisolated let state: CoreBridgeRuntimeState

    private let availability: String
    public nonisolated let boundaries: [CoreBridgeBoundary]

    public init(
        state: CoreBridgeRuntimeState = .generatedBindings,
        availability: String = "generated-bindings",
        boundaries: [CoreBridgeBoundary] = CoreBridgeBoundary.allCases
    ) {
        self.state = state
        self.availability = availability
        self.boundaries = boundaries
    }

    public nonisolated func coreAvailability() -> String {
        availability
    }

    public func declaredBoundaries() async -> [CoreBridgeBoundary] {
        boundaries
    }

    public nonisolated func isDeclared(_ boundary: CoreBridgeBoundary) -> Bool {
        boundaries.contains(boundary)
    }
}
