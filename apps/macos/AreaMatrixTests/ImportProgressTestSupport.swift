@testable import AreaMatrix
import XCTest

extension OnboardingModel {
    var currentImportProgressState: ImportProgressRouteState? {
        guard case let .importProgress(state) = route else { return nil }
        return state
    }
}

@MainActor
func waitForImportResultRoute(
    _ model: OnboardingModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> ImportResultRouteState? {
    for _ in 0 ..< 100 {
        if case let .importResult(state) = model.route { return state }
        await Task.yield()
    }
    XCTFail("Timed out waiting for import result route, got \(model.route)", file: file, line: line)
    return nil
}

actor StaticImportBatchSessionStore: ImportBatchSessionPersisting {
    private let session: ImportBatchSessionSnapshot?
    private var cleared: [String] = []

    init(session: ImportBatchSessionSnapshot?) {
        self.session = session
    }

    func saveSession(_: ImportBatchSessionSnapshot) async {}

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        guard session?.repoPath == repoPath else { return nil }
        return session
    }

    func clearSession(repoPath: String) {
        cleared.append(repoPath)
    }

    func clearedRepoPaths() -> [String] {
        cleared
    }
}

actor ImportProgressFatalCopyErrorMapper: CoreErrorMapping {
    func mapCoreError(_ error: CoreError) async -> CoreErrorMappingSnapshot {
        switch error {
        case .Io: .importProgressFatalCopyError
        default: .importSingleFileError(kind: .internal)
        }
    }
}

extension CoreErrorMappingSnapshot {
    static var importProgressFatalCopyError: CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "文件读写失败",
            severity: .critical,
            suggestedAction: "AreaMatrix 会先确认 staging 状态，再允许重试当前项。",
            recoverability: .fatal,
            rawContext: "import-progress fatal copy retry"
        )
    }
}
