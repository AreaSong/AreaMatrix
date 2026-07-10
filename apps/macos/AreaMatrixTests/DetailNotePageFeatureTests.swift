@testable import AreaMatrix
import CoreServices
import XCTest

final class DetailNotePageFeatureTests: XCTestCase {
    @MainActor
    func testDetailNoteReadWriteNoteCoreLoadsEmptyNoteAndWritesDraftThroughCoreBridgeContract() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 114, currentName: "note.pdf")
        let noteStore = DetailNoteRecordingStore(readResults: [.success(nil)], writeResults: [.success(())])
        let tracker = DetailNoteRecordingInFlightTracker()
        let model = makeDetailNoteTestModel(
            noteStore: noteStore,
            inFlightTracker: tracker
        )

        await model.load(file: file, writeBlock: nil)
        model.createNote()
        model.updateDraft("contract notes")
        await waitForDetailNoteSaveSettled(model)

        await noteStore.assertReadRequests([DetailNoteReadRequest(repoPath: "/tmp/repo", fileID: file.id)])
        await noteStore.assertWriteRequests([DetailNoteWriteRequest(
            repoPath: "/tmp/repo",
            fileID: file.id,
            contentMarkdown: "contract notes"
        )])
        XCTAssertEqual(
            model.state,
            .editing(fileID: file.id, content: "contract notes", saveStatus: .saved, writeBlock: nil)
        )
        await tracker.assertBalancedRequests([
            DetailNoteInFlightRequest(repoPath: "/tmp/repo", relativePath: "\(file.path).md")
        ])
    }

    @MainActor
    func testDetailNoteReadWriteNoteCoreSaveFailureKeepsDraftAndRetryWritesLatestContent() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 115, currentName: "retry.pdf")
        let mapping = CoreErrorMappingSnapshot.detailNoteIo()
        let noteStore = DetailNoteRecordingStore(
            readResults: [.success("old")],
            writeResults: [.failure(CoreError.Io(message: "disk full")), .success(())]
        )
        let model = makeDetailNoteTestModel(
            noteStore: noteStore,
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )

        await model.load(file: file, writeBlock: nil)
        model.updateDraft("new unsaved draft")
        await waitForDetailNoteSaveSettled(model)

        XCTAssertEqual(model.state, .editing(
            fileID: file.id,
            content: "new unsaved draft",
            saveStatus: .failed(mapping),
            writeBlock: nil
        ))

        await model.retrySave()

        await noteStore.assertWriteContents(["new unsaved draft", "new unsaved draft"])
        XCTAssertEqual(
            model.state,
            .editing(fileID: file.id, content: "new unsaved draft", saveStatus: .saved, writeBlock: nil)
        )
    }

    @MainActor
    func testDetailNoteReadWriteNoteCoreCreateNoteRequestsEditorFocus() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 119, currentName: "focus.pdf")
        let model = makeDetailNoteTestModel(
            noteStore: DetailNoteRecordingStore(readResults: [.success(nil)])
        )

        await model.load(file: file, writeBlock: nil)
        model.createNote()

        XCTAssertTrue(model.editorFocusRequest)

        model.consumeEditorFocusRequest()

        XCTAssertFalse(model.editorFocusRequest)
    }

    @MainActor
    func testDetailNoteReadWriteNoteCoreFailedDraftReportsWhenLeavingSelectedFile() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 120, currentName: "leave.pdf")
        let mapping = CoreErrorMappingSnapshot.detailNoteIo()
        let noteStore = DetailNoteRecordingStore(
            readResults: [.success("old")],
            writeResults: [.failure(CoreError.Io(message: "disk full"))]
        )
        let noteModel = makeDetailNoteTestModel(
            noteStore: noteStore,
            errorMapper: StaticCoreErrorMapper(mapping: mapping)
        )
        let listModel = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await noteModel.load(file: file, writeBlock: nil)
        noteModel.updateDraft("unsaved after failure")
        await waitForDetailNoteSaveSettled(noteModel)
        if let failedFileID = noteModel.failedDraftFileIDLeaving(fileID: file.id) {
            listModel.showUnsavedNoteDraftPreserved(fileID: failedFileID)
        }

        XCTAssertEqual(listModel.statusBanner, .unsavedNoteDraftPreserved(fileID: file.id))
    }

    @MainActor
    func testDetailNoteReadWriteNoteCoreReadOnlyAndMissingFilesDisableWritesWithoutClearingExistingNote() async {
        let missingFile = FileEntrySnapshot.detailMetaFixture(
            id: 116,
            currentName: "missing.pdf",
            availability: .missing
        )
        let noteStore = DetailNoteRecordingStore(readResults: [.success("existing note")])
        let model = makeDetailNoteTestModel(noteStore: noteStore)

        await model.load(file: missingFile, writeBlock: .fileMissing)
        model.updateDraft("should not write")

        XCTAssertEqual(model.state, .editing(
            fileID: missingFile.id,
            content: "existing note",
            saveStatus: .saved,
            writeBlock: .fileMissing
        ))
        await noteStore.assertNoWriteRequests()
    }

    @MainActor
    func testDetailNoteReadWriteNoteCoreMainListMapsReadOnlyAndMissingWriteBlocks() {
        let available = FileEntrySnapshot.detailMetaFixture(id: 117, currentName: "available.pdf")
        let missing = FileEntrySnapshot.detailMetaFixture(id: 118, currentName: "missing.pdf", availability: .missing)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [available, missing], isReadOnly: true),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(available)),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        XCTAssertEqual(model.noteWriteBlock(for: available), .repoReadOnly)

        let writableModel = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [missing]),
            fileLister: NoopFileLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(missing)),
            errorMapper: StaticCoreErrorMapper(mapping: .detailMetaFileNotFound())
        )

        XCTAssertEqual(writableModel.noteWriteBlock(for: missing), .fileMissing)
    }

    @MainActor
    func testDetailNoteReadWriteNoteCoreWatcherIgnoresInFlightNoteSidecarWrite() async {
        let repoPath = "/tmp/repo"
        let relativePath = "docs/contracts/note.pdf.md"
        let absolutePath = "\(repoPath)/\(relativePath)"
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
        let signal = MainExternalCreatedFileWatcher.signal(
            repoPath: repoPath,
            absolutePath: absolutePath,
            flags: flags,
            eventID: 9114
        )

        await InFlightFileChangeTracker.shared.mark(repoPath: repoPath, relativePath: relativePath)

        let isInFlight = await InFlightFileChangeTracker.shared.contains(
            repoPath: signal?.repoPath ?? repoPath,
            relativePath: signal?.relativePath ?? relativePath
        )
        await InFlightFileChangeTracker.shared.unmark(repoPath: repoPath, relativePath: relativePath)

        XCTAssertEqual(signal?.relativePath, relativePath)
        XCTAssertTrue(isInFlight)
    }

    func testDetailNoteReadWriteNoteCoreDefaultCoreBridgeReadsAndWritesRealSidecarNote() async throws {
        let repoURL = try makeDetailNoteTemporaryRepositoryURL()
        let sourceRoot = try makeDetailNoteTemporaryRepositoryURL()
        defer {
            removeTestTemporaryItems(repoURL, sourceRoot)
        }
        let sourceURL = sourceRoot.appendingPathComponent("source-note.txt")
        try "source".write(to: sourceURL, atomically: true, encoding: .utf8)

        let bridge = CoreBridge()
        try await bridge.initializeEmptyRepository(repoPath: repoURL.path)
        let entry = try await bridge.importCopiedFile(
            repoPath: repoURL.path,
            sourceURL: sourceURL,
            overrideCategory: "docs",
            overrideFilename: "source-note.txt",
            duplicateStrategy: .keepBoth
        )

        let emptyNote = try await bridge.readNote(repoPath: repoURL.path, fileID: entry.id)

        XCTAssertNil(emptyNote)

        try await bridge.writeNote(repoPath: repoURL.path, fileID: entry.id, contentMarkdown: "# Note")
        let note = try await bridge.readNote(repoPath: repoURL.path, fileID: entry.id)

        XCTAssertEqual(note, "# Note")
    }
}

private struct DetailNoteInFlightRequest: Equatable {
    var repoPath: String
    var relativePath: String
}

private actor DetailNoteRecordingInFlightTracker: InFlightFileChangeTracking {
    private var marks: [DetailNoteInFlightRequest] = []
    private var unmarks: [DetailNoteInFlightRequest] = []

    func mark(repoPath: String, relativePath: String) async {
        marks.append(DetailNoteInFlightRequest(repoPath: repoPath, relativePath: relativePath))
    }

    func unmark(repoPath: String, relativePath: String) async {
        unmarks.append(DetailNoteInFlightRequest(repoPath: repoPath, relativePath: relativePath))
    }

    func contains(repoPath: String, relativePath: String) async -> Bool {
        marks.contains(DetailNoteInFlightRequest(repoPath: repoPath, relativePath: relativePath))
    }

    func assertBalancedRequests(
        _ expectedRequests: [DetailNoteInFlightRequest],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(marks, expectedRequests, file: file, line: line)
        XCTAssertEqual(unmarks, expectedRequests, file: file, line: line)
    }
}

private extension RepositoryOpeningResult {
    static func detailMetaFixture(
        repoPath: String,
        files: [FileEntrySnapshot],
        isReadOnly: Bool
    ) -> RepositoryOpeningResult {
        var opening = RepositoryOpeningResult.detailMetaFixture(repoPath: repoPath, files: files)
        opening.isReadOnly = isReadOnly
        return opening
    }
}

private extension FileEntrySnapshot {
    static func detailMetaFixture(
        id: Int64,
        currentName: String,
        availability: FileAvailabilitySnapshot
    ) -> FileEntrySnapshot {
        var file = FileEntrySnapshot.detailMetaFixture(id: id, currentName: currentName)
        file.availability = availability
        return file
    }
}

private func makeDetailNoteTemporaryRepositoryURL() throws -> URL {
    try makeTestTemporaryDirectory(named: "AreaMatrixDetailNoteTests")
}
