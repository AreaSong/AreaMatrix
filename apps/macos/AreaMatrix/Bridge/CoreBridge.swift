import Foundation

actor CoreBridge {
    enum BridgeState: Equatable, Sendable {
        case placeholder
    }

    private let repoURL: URL?
    private let placeholderState: CoreBridgePlaceholderState

    init(repoURL: URL? = nil, placeholderState: CoreBridgePlaceholderState = .phase0) {
        self.repoURL = repoURL
        self.placeholderState = placeholderState
    }

    nonisolated var state: BridgeState {
        .placeholder
    }

    func currentState() -> CoreBridgePlaceholderState {
        placeholderState
    }

    nonisolated func coreAvailability() -> String {
        "placeholder"
    }

    func declaredBoundaries() -> [CoreBridgeBoundary] {
        CoreBridgeBoundary.allCases
    }

    func requireGeneratedBindings(for boundary: CoreBridgeBoundary) throws -> Never {
        throw CoreBridgeError.generatedBindingsUnavailable(boundary: boundary, state: placeholderState)
    }

    func getVersion() async throws -> Never {
        try requireGeneratedBindings(for: .getVersion)
    }

    func initializeLogging(level: String) async throws -> Never {
        try requireGeneratedBindings(for: .initLogging)
    }

    func validateRepoPath(_ candidateURL: URL) async throws -> Never {
        try requireGeneratedBindings(for: .validateRepoPath)
    }

    func initializeRepo() async throws -> Never {
        try requireGeneratedBindings(for: .initRepo)
    }

    func loadConfig() async throws -> Never {
        try requireGeneratedBindings(for: .loadConfig)
    }

    func updateConfig() async throws -> Never {
        try requireGeneratedBindings(for: .updateConfig)
    }

    func recoverOnStartup() async throws -> Never {
        try requireGeneratedBindings(for: .recoverOnStartup)
    }

    func reindexFromFilesystem() async throws -> Never {
        try requireGeneratedBindings(for: .reindexFromFilesystem)
    }

    func latestScanSession() async throws -> Never {
        try requireGeneratedBindings(for: .getLatestScanSession)
    }

    func resumeScanSession(id: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .resumeScanSession)
    }

    func predictCategory(filename: String) async throws -> Never {
        try requireGeneratedBindings(for: .predictCategory)
    }

    func importFile(from sourceURL: URL) async throws -> Never {
        try requireGeneratedBindings(for: .importFile)
    }

    func deleteFile(id: Int64, hard: Bool) async throws -> Never {
        try requireGeneratedBindings(for: .deleteFile)
    }

    func renameFile(id: Int64, newName: String) async throws -> Never {
        try requireGeneratedBindings(for: .renameFile)
    }

    func moveToCategory(id: Int64, category: String) async throws -> Never {
        try requireGeneratedBindings(for: .moveToCategory)
    }

    func restoreFile(id: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .restoreFile)
    }

    func listFiles() async throws -> Never {
        try requireGeneratedBindings(for: .listFiles)
    }

    func getFile(id: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .getFile)
    }

    func listChanges() async throws -> Never {
        try requireGeneratedBindings(for: .listChanges)
    }

    func listTreeJSON(locale: String) async throws -> Never {
        try requireGeneratedBindings(for: .listTreeJSON)
    }

    func readNote(fileID: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .readNote)
    }

    func writeNote(fileID: Int64, contentMarkdown: String) async throws -> Never {
        try requireGeneratedBindings(for: .writeNote)
    }

    func syncExternalChanges() async throws -> Never {
        try requireGeneratedBindings(for: .syncExternalChanges)
    }

    func getFSEventCursor() async throws -> Never {
        try requireGeneratedBindings(for: .getFSEventCursor)
    }

    func setFSEventCursor(_ cursor: Int64) async throws -> Never {
        try requireGeneratedBindings(for: .setFSEventCursor)
    }

    func repoPathForDiagnostics() -> String? {
        repoURL?.path
    }
}
