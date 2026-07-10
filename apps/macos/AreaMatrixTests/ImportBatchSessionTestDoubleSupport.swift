@testable import AreaMatrix

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

    func waitForClearedRepoPaths(_ expected: [String], attempts: Int = 1000) async -> [String] {
        await waitForActorTestValue(
            on: self,
            attempts: attempts,
            failureMessage: { "Timed out waiting for cleared import batch session repo paths, got \(cleared)" },
            value: {
                cleared == expected ? cleared : nil
            }
        ) ?? cleared
    }
}

actor RecordingImportBatchSessionStore: ImportBatchSessionPersisting {
    private var saved: [ImportBatchSessionSnapshot] = []
    private var cleared: [String] = []
    private var sessionsByRepoPath: [String: ImportBatchSessionSnapshot] = [:]

    func saveSession(_ session: ImportBatchSessionSnapshot) async {
        saved.append(session)
        sessionsByRepoPath[session.repoPath] = session
    }

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        sessionsByRepoPath[repoPath]
    }

    func clearSession(repoPath: String) async {
        cleared.append(repoPath)
        sessionsByRepoPath[repoPath] = nil
    }

    func savedSessions() -> [ImportBatchSessionSnapshot] {
        saved
    }

    func clearedRepoPaths() -> [String] {
        cleared
    }
}
