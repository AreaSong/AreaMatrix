@testable import AreaMatrix

actor MainListIntegrationSuspendedLister: CoreFileListing {
    private var continuation: CheckedContinuation<Void, Never>?
    private var didReceiveRequest = false

    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        didReceiveRequest = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return []
    }

    func waitForRequest() async {
        while !didReceiveRequest {
            await Task.yield()
        }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

typealias MainListIntegrationNoopDetailer = RecordingFileDetailer
typealias MainListIntegrationDetailer = RecordingFileDetailer
typealias MainListIntegrationDiagnosticsCollector = RecordingDiagnosticsCollector
