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
    private var recordedStatusRequests: [StatusRequest] = []
    private var recordedFolderRequests: [FolderRequest] = []

    init(status: LocalModelStatusState, location: LocalModelFolderLocationState) {
        self.status = status
        self.location = location
    }

    func getLocalModelStatus(
        repoPath: String,
        request: LocalModelStatusRequestState
    ) async throws -> LocalModelStatusState {
        recordedStatusRequests.append(StatusRequest(repoPath: repoPath, request: request))
        return status
    }

    func locateLocalModelFolder(
        repoPath: String,
        request: LocalModelFolderRequestState
    ) async throws -> LocalModelFolderLocationState {
        recordedFolderRequests.append(FolderRequest(repoPath: repoPath, request: request))
        return location
    }

    func statusRequests() -> [StatusRequest] {
        recordedStatusRequests
    }

    func folderRequests() -> [FolderRequest] {
        recordedFolderRequests
    }

    func assertStatusRequests(
        _ expectedRequests: [StatusRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedStatusRequests, expectedRequests, file: file, line: line)
    }

    func assertFolderRequests(
        _ expectedRequests: [FolderRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(recordedFolderRequests, expectedRequests, file: file, line: line)
    }
}

final class RecordingLocalModelStorageProvider: LocalModelStorageLocationProviding, @unchecked Sendable {
    private(set) var requestCount = 0
    private let defaultLocation: String

    init(defaultLocation: String) {
        self.defaultLocation = defaultLocation
    }

    func defaultStorageLocation() -> String {
        requestCount += 1
        return defaultLocation
    }
}

@MainActor
final class RecordingInstallHelpOpener: LocalModelInstallHelpOpening {
    private(set) var openCount = 0

    func openLocalModelInstallHelp() throws {
        openCount += 1
    }
}

@MainActor
final class LocalModelStatusRecordingFolderOpener: LocalModelFolderOpening {
    private(set) var locations: [LocalModelFolderLocationState] = []

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
    private(set) var summaries: [String] = []

    func copyLocalModelDiagnostics(_ summary: String) throws {
        summaries.append(summary)
    }
}
