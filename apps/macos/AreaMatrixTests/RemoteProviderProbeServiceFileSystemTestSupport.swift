@testable import AreaMatrix
import Foundation
import XCTest

func makeRemoteProviderProbeTemporaryRepoURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixRemoteProviderProbeServiceTests")
}

@MainActor
func aiCategorySuggestionPrivacyRuleReferenceModel(
    ruleID: String,
    bridge: any CoreAIPrivacyRulesManaging
) -> AIClassificationPrivacyRuleReferenceModel {
    AIClassificationPrivacyRuleReferenceModel(
        repoPath: "/tmp/repo",
        ruleID: ruleID,
        bridge: bridge,
        errorMapper: StaticCoreErrorMapper(mapping: CoreErrorMappingSnapshot.testFixture(
            kind: .db,
            userMessage: "Mapped ai-privacy-rules-core core error",
            severity: .medium,
            suggestedAction: "Open privacy rules",
            recoverability: .userActionRequired,
            rawContext: "ai-category-suggestion ai-privacy-rules-core"
        ))
    )
}

struct ProbeCredentialReaderDouble: RemoteProviderProbeCredentialReading {
    let value: String?

    func credential(reference _: String) -> String? {
        value
    }
}

actor ProbeHTTPTransportRecorder: RemoteProviderProbeHTTPTransporting {
    private let statusCode: UInt32?
    private var requests: [RemoteProviderProbeHTTPRequest] = []

    init(statusCode: UInt32?) {
        self.statusCode = statusCode
    }

    func status(for request: RemoteProviderProbeHTTPRequest) async -> UInt32? {
        requests.append(request)
        return statusCode
    }

    func assertSingleProbeRequest(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> RemoteProviderProbeHTTPRequest? {
        XCTAssertEqual(requests.count, 1, file: file, line: line)
        return requests.first
    }

    func assertNoProbeRequests(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(requests.isEmpty, file: file, line: line)
    }
}

actor ProbePerformerRecorder: RemoteProviderProbePerforming {
    private let outcome: RemoteProviderProbeOutcomeState
    private let httpStatus: UInt32?
    private var plans: [RemoteProviderProbePlanState] = []

    init(outcome: RemoteProviderProbeOutcomeState = .httpResponse, httpStatus: UInt32? = 200) {
        self.outcome = outcome
        self.httpStatus = httpStatus
    }

    func perform(plan: RemoteProviderProbePlanState) async -> RemoteProviderProbeObservationState {
        plans.append(plan)
        return RemoteProviderProbeObservationState(
            probeToken: plan.probeToken,
            outcome: outcome,
            httpStatus: httpStatus
        )
    }

    func recordedPlans() -> [RemoteProviderProbePlanState] {
        plans
    }
}

actor CancellationAwareProbePerformer: RemoteProviderProbePerforming {
    private var plans: [RemoteProviderProbePlanState] = []

    func perform(plan: RemoteProviderProbePlanState) async -> RemoteProviderProbeObservationState {
        plans.append(plan)
        try? await Task.sleep(for: .seconds(30))
        return RemoteProviderProbeObservationState(
            probeToken: plan.probeToken,
            outcome: .connectionFailed,
            httpStatus: nil
        )
    }

    func recordedPlans() -> [RemoteProviderProbePlanState] {
        plans
    }
}

class RemoteProviderProbeURLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Scenario {
        case response(status: Int, body: Data)
        case redirect(location: URL)
        case failure(URLError.Code)
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var scenario: Scenario = .failure(.unknown)

    static func configure(_ scenario: Scenario) {
        lock.lock()
        self.scenario = scenario
        lock.unlock()
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let scenario = Self.scenario
        Self.lock.unlock()
        switch scenario {
        case let .response(status, body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": String(body.count)]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .redirect(location):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": location.absoluteString]
            )!
            client?.urlProtocol(
                self,
                wasRedirectedTo: URLRequest(url: location),
                redirectResponse: response
            )
        case let .failure(code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}
}
