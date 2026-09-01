public protocol CoreVersionReading: Sendable {
    func coreVersion() async throws -> String
}

public protocol CoreVersionLoading: Sendable {
    func coreVersion() async throws -> String
}
