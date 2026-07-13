@testable import AreaMatrix
import XCTest

struct PlatformCapabilityRequest: Equatable {
    var platform: PlatformIdSnapshot
    var appVersion: String
}

struct PlatformDifferencesInspectRequest: Equatable {
    var targetPlatform: BindingTargetPlatformSnapshot
    var bindingVersion: Int64
}

actor PlatformDifferencesRecordingInspector: CoreBindingContractInspecting {
    private let result: Result<BindingContractReportSnapshot, Error>
    private var requestLog = TestRequestLog<PlatformDifferencesInspectRequest>()

    init(result: Result<BindingContractReportSnapshot, Error>) {
        self.result = result
    }

    func inspectBindingContract(
        targetPlatform: BindingTargetPlatformSnapshot,
        bindingVersion: Int64
    ) async throws -> BindingContractReportSnapshot {
        requestLog.append(PlatformDifferencesInspectRequest(
            targetPlatform: targetPlatform,
            bindingVersion: bindingVersion
        ))
        return try result.get()
    }

    func assertBindingContractInspectionRequests(
        _ expectedRequests: [PlatformDifferencesInspectRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRequests, file: file, line: line)
    }
}

actor RecordingPlatformCapabilityLoader: CorePlatformCapabilitiesLoading {
    private let result: Swift.Result<PlatformCapabilitiesSnapshot, Error>
    private var requestLog = TestRequestLog<PlatformCapabilityRequest>()

    init(result: Swift.Result<PlatformCapabilitiesSnapshot, Error>) {
        self.result = result
    }

    func getPlatformCapabilities(
        platform: PlatformIdSnapshot,
        appVersion: String
    ) async throws -> PlatformCapabilitiesSnapshot {
        requestLog.append(PlatformCapabilityRequest(platform: platform, appVersion: appVersion))
        return try result.get()
    }

    func assertPlatformCapabilityRequests(
        _ expectedRequests: [PlatformCapabilityRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        requestLog.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertNoPlatformCapabilityRequests(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertPlatformCapabilityRequests([], file: file, line: line)
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

    func assertRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(count, expectedCount, file: file, line: line)
    }
}
