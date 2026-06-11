@testable import AreaMatrixIOS
import XCTest

@MainActor
final class MissingFileRecoveryPageFeatureTests: XCTestCase {
    func testS4X06LoadsMissingStateFromC418CoreBridge() async {
        let bridge = RecordingMissingFileRecoveryCoreBridge(state: .fixture(fileID: 42))
        let model = MissingFileRecoveryViewModel(repoPath: "/tmp/Repo", fileID: 42, bridge: bridge)

        await model.load()
        let requests = await bridge.requests()

        XCTAssertEqual(requests, [.getState("/tmp/Repo", 42)])
        XCTAssertEqual(model.state?.relativePath, "docs/report.pdf")
        XCTAssertEqual(model.state?.reason, .pathMissing)
        XCTAssertFalse(model.canRemoveRecord)
    }

    func testS4X06TryAgainIsReadOnlyStateRefresh() async {
        let bridge = RecordingMissingFileRecoveryCoreBridge(state: .fixture(fileID: 7))
        let model = MissingFileRecoveryViewModel(repoPath: "/tmp/Repo", fileID: 7, bridge: bridge)

        await model.load()
        await model.tryAgain()
        let requests = await bridge.requests()

        XCTAssertEqual(requests, [
            .getState("/tmp/Repo", 7),
            .getState("/tmp/Repo", 7)
        ])
    }

    func testS4X06RelinkUsesConfirmedCoreRequestAndKeepsHashMismatchVisible() async {
        let bridge = RecordingMissingFileRecoveryCoreBridge(
            state: .fixture(fileID: 9),
            relinkReport: .fixture(fileID: 9, status: .hashMismatch, hashMatched: false)
        )
        let fileAccess = RecordingMissingFileRecoveryFileAccess()
        let model = MissingFileRecoveryViewModel(
            repoPath: "/tmp/Repo",
            fileID: 9,
            bridge: bridge,
            fileAccess: fileAccess
        )

        await model.load()
        model.selectRelinkFile(URL(fileURLWithPath: "/tmp/Selected/report.pdf"))
        await model.relinkSelectedFile()
        let requests = await bridge.requests()

        XCTAssertEqual(requests, [
            .getState("/tmp/Repo", 9),
            .relink("/tmp/Repo", .init(fileID: 9, newPath: "/tmp/Selected/report.pdf", confirmed: true))
        ])
        XCTAssertEqual(fileAccess.beganPaths, ["/tmp/Selected/report.pdf"])
        XCTAssertEqual(fileAccess.stoppedPaths, ["/tmp/Selected/report.pdf"])
        XCTAssertEqual(model.report?.status, .hashMismatch)
        XCTAssertEqual(model.actionError?.message, "Selected file does not match the missing record.")
    }

    func testS4X06LocateFileRequiresPickerSelectionBeforeRelink() async {
        let bridge = RecordingMissingFileRecoveryCoreBridge(state: .fixture(fileID: 10))
        let model = MissingFileRecoveryViewModel(repoPath: "/tmp/Repo", fileID: 10, bridge: bridge)

        await model.load()
        await model.relinkSelectedFile()
        let requests = await bridge.requests()

        XCTAssertEqual(requests, [.getState("/tmp/Repo", 10)])
        XCTAssertFalse(model.canRelink)
        XCTAssertEqual(model.selectedRelinkPath, "")
    }

    func testS4X06LocateFilePermissionFailureStaysVisibleAndSkipsCoreRelink() async {
        let bridge = RecordingMissingFileRecoveryCoreBridge(state: .fixture(fileID: 13))
        let fileAccess = RecordingMissingFileRecoveryFileAccess(error: .permissionDenied("/private/report.pdf"))
        let model = MissingFileRecoveryViewModel(
            repoPath: "/tmp/Repo",
            fileID: 13,
            bridge: bridge,
            fileAccess: fileAccess
        )

        await model.load()
        model.selectRelinkFile(URL(fileURLWithPath: "/private/report.pdf"))
        await model.relinkSelectedFile()
        let requests = await bridge.requests()

        XCTAssertEqual(requests, [.getState("/tmp/Repo", 13)])
        XCTAssertEqual(model.actionError, .permissionDenied("/private/report.pdf"))
    }

    func testS4X06RemoveRecordRequiresConfirmationAndNeverClaimsFileDeletion() async {
        let bridge = RecordingMissingFileRecoveryCoreBridge(
            state: .fixture(fileID: 11),
            removeReport: .fixture(
                fileID: 11,
                status: .recordRemoved,
                recordRemoved: true,
                fileDeleted: false,
                changeLogAction: "missing_file_record_removed"
            )
        )
        let model = MissingFileRecoveryViewModel(repoPath: "/tmp/Repo", fileID: 11, bridge: bridge)

        await model.load()
        await model.removeRecord()
        model.removeRecordConfirmed = true
        await model.removeRecord()
        let requests = await bridge.requests()

        XCTAssertEqual(requests, [
            .getState("/tmp/Repo", 11),
            .remove("/tmp/Repo", .init(fileID: 11, confirmed: true))
        ])
        XCTAssertTrue(model.report?.recordRemoved == true)
        XCTAssertEqual(model.report?.fileDeleted, false)
        XCTAssertEqual(model.report?.changeLogAction, "missing_file_record_removed")
    }

    func testS4X06IOSProductionEntriesRouteMissingDetailActionToRecoverySheet() throws {
        let appSource = try Self.readSource("../AreaMatrix/App/AreaMatrixIOSApp.swift")
        let routeSource = try Self.readSource(
            "../AreaMatrix/Features/Onboarding/ConnectRepositoryRouteDestinationView.swift"
        )
        let librarySource = try Self.readSource("../AreaMatrix/Features/Library/MobileLibraryView.swift")
        let detailSource = try Self.readSource("../AreaMatrix/Features/Detail/MobileFileDetailView.swift")

        XCTAssertTrue(appSource.contains("@State private var pendingMissingFileRecoveryRoute"))
        XCTAssertTrue(appSource.contains("onOpenMissingRecovery: { fileID in"))
        XCTAssertTrue(appSource.contains(
            "openMissingFileRecovery(repoPath: connection.validation.repoPath, fileID: fileID)"
        ))
        XCTAssertTrue(appSource.contains(".sheet(item: $pendingMissingFileRecoveryRoute)"))
        XCTAssertTrue(appSource.contains("MissingFileRecoveryView("))
        XCTAssertTrue(routeSource.contains("@State private var pendingMissingFileRecoveryRoute"))
        XCTAssertTrue(routeSource.contains("onOpenMissingRecovery: { fileID in"))
        XCTAssertTrue(routeSource.contains("MissingFileRecoveryView("))
        XCTAssertTrue(librarySource.contains("onOpenMissingRecovery: onOpenMissingRecovery"))
        XCTAssertTrue(detailSource.contains("onOpenMissingRecovery(fileID)"))
    }

    func testS4X06IOSUsesPlatformFileImporterAndSecurityScopedRelinkAccess() throws {
        let viewSource = try Self.readSource("../AreaMatrix/Features/Recovery/MissingFileRecoveryView.swift")
        let accessSource = try Self.readSource(
            "../AreaMatrix/Features/Recovery/MissingFileRecoveryFileAccess.swift"
        )

        XCTAssertTrue(viewSource.contains(".fileImporter("))
        XCTAssertTrue(viewSource.contains("allowedContentTypes: [.item]"))
        XCTAssertTrue(viewSource.contains("handleLocateFilePickerResult"))
        XCTAssertTrue(viewSource.contains("selectRelinkFile(url)"))
        XCTAssertFalse(viewSource.contains("TextField(\"Selected file path\""))
        XCTAssertTrue(accessSource.contains("startAccessingSecurityScopedResource()"))
        XCTAssertTrue(accessSource.contains("stopAccessingSecurityScopedResource()"))
    }

    private static func readSource(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let sourceURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
            .standardizedFileURL
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

private actor RecordingMissingFileRecoveryCoreBridge: MissingFileRecoveryCoreBridge {
    enum Request: Equatable {
        case getState(String, Int64)
        case relink(String, MissingFileRelinkRequest)
        case remove(String, MissingFileRemoveRecordRequest)
    }

    private var recordedRequests: [Request] = []
    private let state: MissingFileRecoveryState
    private let relinkReport: MissingFileRecoveryReport
    private let removeReport: MissingFileRecoveryReport

    init(
        state: MissingFileRecoveryState,
        relinkReport: MissingFileRecoveryReport? = nil,
        removeReport: MissingFileRecoveryReport? = nil
    ) {
        self.state = state
        self.relinkReport = relinkReport ?? .fixture(fileID: state.fileID, status: .relinked, hashMatched: true)
        self.removeReport = removeReport ?? .fixture(fileID: state.fileID, status: .recordRemoved, recordRemoved: true)
    }

    func getMissingFileState(repoPath: String, fileID: Int64) async throws -> MissingFileRecoveryState {
        recordedRequests.append(.getState(repoPath, fileID))
        return state
    }

    func relinkMissingFile(
        repoPath: String,
        request: MissingFileRelinkRequest
    ) async throws -> MissingFileRecoveryReport {
        recordedRequests.append(.relink(repoPath, request))
        return relinkReport
    }

    func removeMissingFileRecord(
        repoPath: String,
        request: MissingFileRemoveRecordRequest
    ) async throws -> MissingFileRecoveryReport {
        recordedRequests.append(.remove(repoPath, request))
        return removeReport
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private final class RecordingMissingFileRecoveryFileAccess: MissingFileRecoveryFileAccessing, @unchecked Sendable {
    private let error: MissingFileRecoveryError?

    init(error: MissingFileRecoveryError? = nil) {
        self.error = error
    }

    private(set) var beganPaths: [String] = []
    private(set) var stoppedPaths: [String] = []

    func beginAccessing(_ url: URL) throws -> MissingFileRecoveryScopedFileAccess {
        if let error {
            throw error
        }
        beganPaths.append(url.path)
        return MissingFileRecoveryScopedFileAccess { [weak self] in
            self?.stoppedPaths.append(url.path)
        }
    }
}

private extension MissingFileRecoveryState {
    static func fixture(fileID: Int64) -> MissingFileRecoveryState {
        MissingFileRecoveryState(
            fileID: fileID,
            relativePath: "docs/report.pdf",
            lastKnownPath: "/tmp/Repo/docs/report.pdf",
            lastSeenAt: 1_700_000_000,
            reason: .pathMissing,
            expectedHashSha256: "hash",
            canLocate: true,
            canTryAgain: true,
            canRemoveRecord: true,
            removeRecordRequiresConfirmation: true,
            canRunRescan: false,
            rescanDisabledReason: "iOS uses permission recovery, not manual rescan."
        )
    }
}

private extension MissingFileRecoveryReport {
    static func fixture(
        fileID: Int64,
        status: MissingFileRecoveryStatus,
        hashMatched: Bool = false,
        recordRemoved: Bool = false,
        fileDeleted: Bool = false,
        changeLogAction: String? = nil
    ) -> MissingFileRecoveryReport {
        MissingFileRecoveryReport(
            fileID: fileID,
            status: status,
            previousPath: "docs/report.pdf",
            currentPath: status == .relinked ? "/tmp/Selected/report.pdf" : nil,
            hashMatched: hashMatched,
            recordRemoved: recordRemoved,
            fileDeleted: fileDeleted,
            changeLogAction: changeLogAction,
            message: nil
        )
    }
}
