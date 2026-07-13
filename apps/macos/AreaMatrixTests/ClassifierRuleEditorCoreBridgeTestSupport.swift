@testable import AreaMatrix
import XCTest

extension RecordingCoreErrorMapper {
    static func aiSettings() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.testFixture(
                kind: .io,
                userMessage: String(describing: error),
                severity: .medium,
                suggestedAction: "Retry save",
                recoverability: .retryable,
                rawContext: "ai-settings"
            )
        }
    }

    static func localModelStatus() -> RecordingCoreErrorMapper {
        RecordingCoreErrorMapper { error in
            CoreErrorMappingSnapshot.testFixture(
                kind: .io,
                userMessage: String(describing: error),
                severity: .medium,
                suggestedAction: "Retry status check",
                recoverability: .retryable,
                rawContext: "local-model-status"
            )
        }
    }
}

actor RecordingLocalModelReader: CoreLocalModelStatusReading {
    struct StatusRequest: Equatable {
        var repoPath: String
        var request: LocalModelStatusRequestState
    }

    struct FolderRequest: Equatable {
        var repoPath: String
        var request: LocalModelFolderRequestState
    }

    private let status: LocalModelStatusState
    private let location: LocalModelFolderLocationState
    private var statusRequestLog = TestRequestLog<StatusRequest>()
    private var folderRequestLog = TestRequestLog<FolderRequest>()

    init(status: LocalModelStatusState, location: LocalModelFolderLocationState) {
        self.status = status
        self.location = location
    }

    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState {
        statusRequestLog.append(StatusRequest(repoPath: repoPath, request: request))
        return status
    }

    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState {
        folderRequestLog.append(FolderRequest(repoPath: repoPath, request: request))
        return location
    }

    func assertStatusRequests(
        _ expectedRequests: [StatusRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        statusRequestLog.assertRequests(expectedRequests, file: file, line: line)
    }

    func assertFolderRequests(
        _ expectedRequests: [FolderRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        folderRequestLog.assertRequests(expectedRequests, file: file, line: line)
    }
}

final class RecordingLocalModelStorageProvider: LocalModelStorageLocationProviding, @unchecked Sendable {
    private var requestCount = 0
    private let defaultLocation: String

    init(defaultLocation: String) {
        self.defaultLocation = defaultLocation
    }

    func defaultStorageLocation() -> String {
        requestCount += 1
        return defaultLocation
    }

    func assertRequestCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(requestCount, expectedCount, file: file, line: line)
    }
}

@MainActor
final class RecordingInstallHelpOpener: LocalModelInstallHelpOpening {
    private var openCount = 0

    func openLocalModelInstallHelp() throws {
        openCount += 1
    }
}

@MainActor
final class LocalModelStatusRecordingFolderOpener: LocalModelFolderOpening {
    private var locations: [LocalModelFolderLocationState] = []

    func openLocalModelFolder(_ location: LocalModelFolderLocationState) throws {
        locations.append(location)
    }

    func assertOpenedFolderPaths(
        _ expectedFolderPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            locations.map(\.folderPath),
            expectedFolderPaths,
            file: file,
            line: line
        )
    }
}

@MainActor
final class RecordingDiagnosticsCopier: LocalModelDiagnosticsCopying {
    private var summaries: [String] = []

    func copyLocalModelDiagnostics(_ summary: String) throws {
        summaries.append(summary)
    }

    func assertCopiedSummaries(
        _ expectedSummaries: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(summaries, expectedSummaries, file: file, line: line)
    }
}
