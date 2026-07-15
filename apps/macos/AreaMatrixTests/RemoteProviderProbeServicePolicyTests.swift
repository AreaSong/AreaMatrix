@testable import AreaMatrix
import Foundation
import XCTest

final class RemoteProviderProbeServicePolicyTests: XCTestCase {
    func testServiceBuildsBearerRequestWithoutReturningCredential() async throws {
        let transport = ProbeHTTPTransportRecorder(statusCode: 200)
        let service = RemoteProviderProbeService(
            credentialReader: ProbeCredentialReaderDouble(value: "test-secret"),
            transport: transport
        )

        let observation = await service.perform(plan: plan(authorization: .bearer))
        let recordedRequest = await transport.assertSingleProbeRequest()
        let request = try XCTUnwrap(recordedRequest)

        XCTAssertEqual(observation.outcome, .httpResponse)
        XCTAssertEqual(observation.httpStatus, 200)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.headers["Authorization"], "Bearer test-secret")
        XCTAssertEqual(request.headers["User-Agent"], "AreaMatrix")
        XCTAssertFalse(String(describing: observation).contains("test-secret"))
    }

    func testServiceBuildsAnthropicHeadersFromCorePlan() async throws {
        let transport = ProbeHTTPTransportRecorder(statusCode: 401)
        let service = RemoteProviderProbeService(
            credentialReader: ProbeCredentialReaderDouble(value: "anthropic-secret"),
            transport: transport
        )

        let observation = await service.perform(plan: plan(
            headers: [RemoteProviderProbeHeaderState(name: "anthropic-version", value: "2023-06-01")],
            authorization: .anthropicAPIKey
        ))
        let recordedRequest = await transport.assertSingleProbeRequest()
        let request = try XCTUnwrap(recordedRequest)

        XCTAssertEqual(observation.httpStatus, 401)
        XCTAssertEqual(request.headers["x-api-key"], "anthropic-secret")
        XCTAssertEqual(request.headers["anthropic-version"], "2023-06-01")
        XCTAssertNil(request.headers["Authorization"])
    }

    func testServiceReportsCredentialUnavailableWithoutStartingTransport() async {
        let transport = ProbeHTTPTransportRecorder(statusCode: 200)
        let service = RemoteProviderProbeService(
            credentialReader: ProbeCredentialReaderDouble(value: nil),
            transport: transport
        )

        let observation = await service.perform(plan: plan(authorization: .bearer))

        XCTAssertEqual(observation.outcome, .credentialUnavailable)
        XCTAssertNil(observation.httpStatus)
        await transport.assertNoProbeRequests()
    }

    func testServiceRejectsRedirectOrBodyPlansBeforeStartingTransport() async {
        let transport = ProbeHTTPTransportRecorder(statusCode: 200)
        let service = RemoteProviderProbeService(
            credentialReader: ProbeCredentialReaderDouble(value: "test-secret"),
            transport: transport
        )

        let redirect = await service.perform(plan: plan(followRedirects: true))
        let body = await service.perform(plan: plan(maximumResponseBodyBytes: 1))

        XCTAssertEqual(redirect.outcome, .connectionFailed)
        XCTAssertEqual(body.outcome, .connectionFailed)
        await transport.assertNoProbeRequests()
    }

    func testServiceRejectsEndpointUserInfoBeforeStartingTransport() async {
        let transport = ProbeHTTPTransportRecorder(statusCode: 200)
        let service = RemoteProviderProbeService(
            credentialReader: ProbeCredentialReaderDouble(value: "test-secret"),
            transport: transport
        )

        let observation = await service.perform(plan: plan(
            url: "https://user:password@provider.example.test/v1/models/test-model"
        ))

        XCTAssertEqual(observation.outcome, .connectionFailed)
        await transport.assertNoProbeRequests()
    }

    func testURLSessionTransportReturnsRedirectStatusWithoutFollowingLocation() async throws {
        let redirectURL = try XCTUnwrap(
            URL(string: "https://redirected.example.test/credential-target")
        )
        RemoteProviderProbeURLProtocolStub.configure(.redirect(location: redirectURL))
        let transport = URLSessionRemoteProviderProbeTransport(
            protocolClasses: [RemoteProviderProbeURLProtocolStub.self]
        )

        let status = await transport.status(for: httpRequest())

        XCTAssertEqual(status, 302)
    }

    func testURLSessionTransportSanitizesTimeoutAsMissingStatus() async {
        RemoteProviderProbeURLProtocolStub.configure(.failure(.timedOut))
        let transport = URLSessionRemoteProviderProbeTransport(
            protocolClasses: [RemoteProviderProbeURLProtocolStub.self]
        )

        let status = await transport.status(for: httpRequest())

        XCTAssertNil(status)
    }

    private func plan(
        url: String = "https://provider.example.test/v1/models/test-model",
        headers: [RemoteProviderProbeHeaderState] = [],
        authorization: RemoteProviderProbeAuthorizationState = .bearer,
        maximumResponseBodyBytes: UInt64 = 0,
        followRedirects: Bool = false
    ) -> RemoteProviderProbePlanState {
        RemoteProviderProbePlanState(
            keyReference: "keychain:remote-ai-test",
            probeToken: "probe:remote-provider:test",
            method: .get,
            url: url,
            headers: headers,
            authorization: authorization,
            timeoutMilliseconds: 10000,
            maximumResponseBodyBytes: maximumResponseBodyBytes,
            followRedirects: followRedirects
        )
    }

    private func httpRequest() -> RemoteProviderProbeHTTPRequest {
        RemoteProviderProbeHTTPRequest(
            url: URL(string: "https://provider.example.test/probe")!,
            method: "GET",
            headers: ["Authorization": "Bearer test-secret"],
            timeout: 1
        )
    }
}
