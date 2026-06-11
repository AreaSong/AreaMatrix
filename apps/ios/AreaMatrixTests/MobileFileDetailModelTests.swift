@testable import AreaMatrixIOS
import Foundation
import XCTest

@MainActor
final class MobileFileDetailModelTests: XCTestCase {
    func testLoadMetadataUsesGetFileAndKeepsLogAndNoteLazy() async {
        let bridge = FakeMobileFileDetailCoreBridge(metadata: .fixture(id: 7, name: "report.pdf"))
        let model = MobileFileDetailViewModel(repoPath: "/tmp/Repo", fileID: 7, bridge: bridge)

        await model.loadMetadataIfNeeded()

        XCTAssertEqual(model.metadataState.file?.currentName, "report.pdf")
        XCTAssertEqual(model.changeLogState, .notLoaded)
        XCTAssertEqual(model.noteState, .notLoaded)
        let metadataRequests = await bridge.metadataRequestsSnapshot()
        let changeRequests = await bridge.changeRequestsSnapshot()
        let noteRequests = await bridge.noteRequestsSnapshot()
        XCTAssertEqual(metadataRequests, [
            MobileDetailMetadataRequest(repoPath: "/tmp/Repo", fileID: 7)
        ])
        XCTAssertTrue(changeRequests.isEmpty)
        XCTAssertTrue(noteRequests.isEmpty)
    }

    func testLogAndNoteLoadOnlyWhenSelected() async {
        let change = MobileFileChangeLogEntry.fixture(id: 3, fileID: 7, action: "imported")
        let bridge = FakeMobileFileDetailCoreBridge(
            metadata: .fixture(id: 7, name: "report.pdf"),
            changes: [change],
            note: "Reviewed from mobile."
        )
        let model = MobileFileDetailViewModel(repoPath: "/tmp/Repo", fileID: 7, bridge: bridge)

        await model.loadMetadataIfNeeded()
        model.selectedSegment = .log
        await model.loadSelectedSegmentIfNeeded()
        model.selectedSegment = .note
        await model.loadSelectedSegmentIfNeeded()

        XCTAssertEqual(model.changeLogState, .loaded([change]))
        XCTAssertEqual(model.noteState, .loaded("Reviewed from mobile."))
        let changeRequests = await bridge.changeRequestsSnapshot()
        let noteRequests = await bridge.noteRequestsSnapshot()
        XCTAssertEqual(changeRequests.map(\.filter), [.detail(fileID: 7)])
        XCTAssertEqual(noteRequests, [
            MobileDetailNoteRequest(repoPath: "/tmp/Repo", fileID: 7)
        ])
    }

    func testMissingMetadataExposesRecoveryRouteIntentWithoutCallingRecoveryCore() async {
        let bridge = FakeMobileFileDetailCoreBridge(
            metadata: .fixture(id: 9, name: "missing.pdf", availability: .missing)
        )
        let model = MobileFileDetailViewModel(repoPath: "/tmp/Repo", fileID: 9, bridge: bridge)

        await model.loadMetadataIfNeeded()
        model.requestMissingRecoveryRoute()

        XCTAssertTrue(model.canRequestMissingRecovery)
        XCTAssertEqual(model.missingRecoveryRouteFileID, 9)
        let changeRequests = await bridge.changeRequestsSnapshot()
        let noteRequests = await bridge.noteRequestsSnapshot()
        XCTAssertTrue(changeRequests.isEmpty)
        XCTAssertTrue(noteRequests.isEmpty)
    }

    func testSectionFailureDoesNotDiscardLoadedMetadata() async {
        let bridge = FakeMobileFileDetailCoreBridge(
            metadata: .fixture(id: 11, name: "note.pdf"),
            noteError: .database("notes locked")
        )
        let model = MobileFileDetailViewModel(repoPath: "/tmp/Repo", fileID: 11, bridge: bridge)

        await model.loadMetadataIfNeeded()
        model.selectedSegment = .note
        await model.loadSelectedSegmentIfNeeded()

        XCTAssertEqual(model.metadataState.file?.id, 11)
        XCTAssertEqual(model.noteState, .failed(.database("notes locked")))
    }

    func testLiveBridgeLoadsDetailMetadataLogAndNoteThroughCore() async throws {
        let repo = try makeTemporaryRepositoryURL()
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AreaMatrixIOSDetail-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: repo)
            try? FileManager.default.removeItem(at: sourceDir)
        }
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let source = sourceDir.appendingPathComponent("detail.jpg")
        try Data("detail-bytes".utf8).write(to: source)
        let bridge = LiveMobileRepositoryCoreBridge()

        try await bridge.initializeEmptyRepository(repoPath: repo.path)
        let imported = try await bridge.importCapturedPhoto(request: CameraImportCoreRequest(
            repoPath: repo.path,
            sourceURL: source,
            filename: "detail.jpg",
            category: "docs",
            duplicateStrategy: .skip
        ))
        let metadata = try await bridge.getFile(repoPath: repo.path, fileID: imported.id)
        let changes = try await bridge.listChanges(repoPath: repo.path, filter: .detail(fileID: imported.id))
        let note = try await bridge.readNote(repoPath: repo.path, fileID: imported.id)

        XCTAssertEqual(metadata.id, imported.id)
        XCTAssertEqual(metadata.currentName, imported.currentName)
        XCTAssertEqual(metadata.availability, .available)
        XCTAssertTrue(changes.contains { $0.fileID == imported.id && $0.action == "imported" })
        XCTAssertNil(note)
    }
}

private struct MobileDetailMetadataRequest: Equatable, Sendable {
    var repoPath: String
    var fileID: Int64
}

private struct MobileDetailChangeRequest: Equatable, Sendable {
    var repoPath: String
    var filter: MobileFileDetailChangeFilter
}

private struct MobileDetailNoteRequest: Equatable, Sendable {
    var repoPath: String
    var fileID: Int64
}

private actor FakeMobileFileDetailCoreBridge: MobileFileDetailCoreBridge {
    private let metadata: Result<MobileFileDetailMetadata, MobileFileDetailError>
    private let changes: Result<[MobileFileChangeLogEntry], MobileFileDetailError>
    private let note: Result<String?, MobileFileDetailError>
    private var metadataRequests: [MobileDetailMetadataRequest] = []
    private var changeRequests: [MobileDetailChangeRequest] = []
    private var noteRequests: [MobileDetailNoteRequest] = []

    init(
        metadata: MobileFileDetailMetadata,
        changes: [MobileFileChangeLogEntry] = [],
        note: String? = nil,
        noteError: MobileFileDetailError? = nil
    ) {
        self.metadata = .success(metadata)
        self.changes = .success(changes)
        self.note = noteError.map { Result<String?, MobileFileDetailError>.failure($0) } ?? .success(note)
    }

    func getFile(repoPath: String, fileID: Int64) async throws -> MobileFileDetailMetadata {
        metadataRequests.append(MobileDetailMetadataRequest(repoPath: repoPath, fileID: fileID))
        return try metadata.get()
    }

    func listChanges(
        repoPath: String,
        filter: MobileFileDetailChangeFilter
    ) async throws -> [MobileFileChangeLogEntry] {
        changeRequests.append(MobileDetailChangeRequest(repoPath: repoPath, filter: filter))
        return try changes.get()
    }

    func readNote(repoPath: String, fileID: Int64) async throws -> String? {
        noteRequests.append(MobileDetailNoteRequest(repoPath: repoPath, fileID: fileID))
        return try note.get()
    }

    func metadataRequestsSnapshot() -> [MobileDetailMetadataRequest] {
        metadataRequests
    }

    func changeRequestsSnapshot() -> [MobileDetailChangeRequest] {
        changeRequests
    }

    func noteRequestsSnapshot() -> [MobileDetailNoteRequest] {
        noteRequests
    }
}

private extension MobileFileDetailMetadata {
    static func fixture(
        id: Int64,
        name: String,
        availability: MobileFileDetailAvailability = .available
    ) -> MobileFileDetailMetadata {
        MobileFileDetailMetadata(
            id: id,
            path: "docs/\(name)",
            originalName: name,
            currentName: name,
            category: "docs",
            sizeBytes: 128,
            hashSha256: "hash-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            availability: availability,
            importedAt: 1,
            updatedAt: 2
        )
    }
}

private extension MobileFileChangeLogEntry {
    static func fixture(id: Int64, fileID: Int64, action: String) -> MobileFileChangeLogEntry {
        MobileFileChangeLogEntry(
            id: id,
            fileID: fileID,
            filename: "report.pdf",
            category: "docs",
            action: action,
            detailJSON: #"{"source":"ios-test"}"#,
            occurredAt: 3
        )
    }
}
