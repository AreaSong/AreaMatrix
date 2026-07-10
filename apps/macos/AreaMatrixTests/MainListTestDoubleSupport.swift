@testable import AreaMatrix
import XCTest

typealias MainListIntegrationDetailer = RecordingFileDetailer

typealias MainListIntegrationDiagnosticsCollector = RecordingDiagnosticsCollector

typealias MainListIntegrationNoopDetailer = RecordingFileDetailer

typealias MainListRecordingFileLister = RecordingFileLister

typealias MainListRecordingSearchQuerying = RecordingSearchQuerying

typealias MainListSearchRequestRecord = SearchQueryRequestRecord

typealias MainListSmartListRequestRecord = SmartListRunRequestRecord

@MainActor
func requireSidebarRow(
    _ tree: RepositoryTreeNodeSnapshot,
    id: String,
    message: String? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) -> RepositorySidebarRowSnapshot? {
    guard let row = tree.sidebarRow(id: id) else {
        XCTFail(message ?? "Expected sidebar row \(id)", file: file, line: line)
        return nil
    }
    return row
}

struct MainListFallbackRequestRecord: Equatable {
    var repoPath: String
    var request: AiFallbackStatusRequest
}

actor MainListRecordingSemanticSearcher: CoreSemanticSearching {
    private let page: SearchResultPageSnapshot

    init(page: SearchResultPageSnapshot) {
        self.page = page
    }

    func semanticSearch(repoPath _: String,
                        request _: SearchQueryRequestSnapshot) async throws -> SearchResultPageSnapshot {
        page
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        throw CoreError.Internal(message: "semantic-search ai-fallback-core test does not build the semantic index")
    }
}

actor MainListRecordingSemanticFallbackReader: CoreSemanticFallbackStatusReading {
    private let status: AiFallbackStatus
    private var requests: [MainListFallbackRequestRecord] = []

    init(status: AiFallbackStatus) {
        self.status = status
    }

    func semanticFallbackStatus(repoPath: String, request: AiFallbackStatusRequest) async throws -> AiFallbackStatus {
        requests.append(MainListFallbackRequestRecord(repoPath: repoPath, request: request))
        return status
    }

    func recordedRequests() -> [MainListFallbackRequestRecord] {
        requests
    }
}

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
        _ = await waitForActorTestValue(
            on: self,
            failureMessage: { "Timed out waiting for main list request" },
            value: {
                didReceiveRequest ? true : nil
            }
        )
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
