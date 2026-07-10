@testable import AreaMatrix
import XCTest

struct PlatformCapabilityRequest: Equatable {
    var platform: PlatformIdSnapshot
    var appVersion: String
}

actor RecordingPlatformCapabilityLoader: CorePlatformCapabilitiesLoading {
    private let result: Swift.Result<PlatformCapabilitiesSnapshot, Error>
    private var capturedRequests: [PlatformCapabilityRequest] = []

    init(result: Swift.Result<PlatformCapabilitiesSnapshot, Error>) {
        self.result = result
    }

    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        capturedRequests.append(PlatformCapabilityRequest(platform: platform, appVersion: appVersion))
        return try result.get()
    }

    func assertRequests(
        _ expectedRequests: [PlatformCapabilityRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(capturedRequests, expectedRequests, file: file, line: line)
    }

    func assertNoRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertRequests([], file: file, line: line)
    }
}

actor StaticCoreVersionReader: CoreVersionReading {
    private let result: Result<String, Error>
    private var count = 0

    init(version: String) {
        result = .success(version)
    }

    init(result: Result<String, Error>) {
        self.result = result
    }

    func coreVersion() async throws -> String {
        count += 1
        return try result.get()
    }

    func requestCount() -> Int {
        count
    }
}
