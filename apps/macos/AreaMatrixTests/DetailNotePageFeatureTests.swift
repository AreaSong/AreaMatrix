import CoreServices
import XCTest
@testable import AreaMatrix

final class DetailNotePageFeatureTests: XCTestCase {
    @MainActor
    func testS114C114LoadsEmptyNoteAndWritesDraftThroughCoreBridgeContract() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 114, currentName: "note.pdf")
        let noteStore = DetailNoteRecordingStore(readResults: [.success(nil)], writeResults: [.success(())])
        let tracker = DetailNoteRecordingInFlightTracker()
        let model = DetailNoteModel(
            repoPath: "/tmp/repo",
            noteStore: noteStore,
            errorMapper: DetailMetaErrorMapper(mapping: .detailNoteIo()),
            inFlightTracker: tracker,
            debounceNanoseconds: 1
        )

        await model.load(file: file, writeBlock: nil)
        model.createNote()
        model.updateDraft("contract notes")
        await waitForDetailNoteSave(model)
        let reads = await noteStore.recordedReadRequests()
        let writes = await noteStore.recordedWriteRequests()
        let marks = await tracker.recordedMarks()
        let unmarks = await tracker.recordedUnmarks()

        XCTAssertEqual(reads, [DetailNoteReadRequest(repoPath: "/tmp/repo", fileID: file.id)])
        XCTAssertEqual(writes, [DetailNoteWriteRequest(
            repoPath: "/tmp/repo",
            fileID: file.id,
            contentMarkdown: "contract notes"
        )])
        XCTAssertEqual(model.state, .editing(fileID: file.id, content: "contract notes", saveStatus: .saved, writeBlock: nil))
        XCTAssertEqual(marks, [DetailNoteInFlightRequest(repoPath: "/tmp/repo", relativePath: "\(file.path).md")])
        XCTAssertEqual(unmarks, marks)
    }

    @MainActor
    func testS114C114SaveFailureKeepsDraftAndRetryWritesLatestContent() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 115, currentName: "retry.pdf")
        let mapping = CoreErrorMappingSnapshot.detailNoteIo()
        let noteStore = DetailNoteRecordingStore(
            readResults: [.success("old")],
            writeResults: [.failure(CoreError.Io(message: "disk full")), .success(())]
        )
        let model = DetailNoteModel(
            repoPath: "/tmp/repo",
            noteStore: noteStore,
            errorMapper: DetailMetaErrorMapper(mapping: mapping),
            debounceNanoseconds: 1
        )

        await model.load(file: file, writeBlock: nil)
        model.updateDraft("new unsaved draft")
        await waitForDetailNoteSave(model)

        XCTAssertEqual(model.state, .editing(
            fileID: file.id,
            content: "new unsaved draft",
            saveStatus: .failed(mapping),
            writeBlock: nil
        ))

        await model.retrySave()
        let writes = await noteStore.recordedWriteRequests()

        XCTAssertEqual(writes.map(\.contentMarkdown), ["new unsaved draft", "new unsaved draft"])
        XCTAssertEqual(model.state, .editing(fileID: file.id, content: "new unsaved draft", saveStatus: .saved, writeBlock: nil))
    }

    @MainActor
    func testS114C114CreateNoteRequestsEditorFocus() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 119, currentName: "focus.pdf")
        let model = DetailNoteModel(
            repoPath: "/tmp/repo",
            noteStore: DetailNoteRecordingStore(readResults: [.success(nil)]),
            errorMapper: DetailMetaErrorMapper(mapping: .detailNoteIo()),
            debounceNanoseconds: 1
        )

        await model.load(file: file, writeBlock: nil)
        model.createNote()

        XCTAssertTrue(model.editorFocusRequest)

        model.consumeEditorFocusRequest()

        XCTAssertFalse(model.editorFocusRequest)
    }

    @MainActor
    func testS114C114FailedDraftReportsWhenLeavingSelectedFile() async {
        let file = FileEntrySnapshot.detailMetaFixture(id: 120, currentName: "leave.pdf")
        let mapping = CoreErrorMappingSnapshot.detailNoteIo()
        let noteStore = DetailNoteRecordingStore(
            readResults: [.success("old")],
            writeResults: [.failure(CoreError.Io(message: "disk full"))]
        )
        let noteModel = DetailNoteModel(
            repoPath: "/tmp/repo",
            noteStore: noteStore,
            errorMapper: DetailMetaErrorMapper(mapping: mapping),
            debounceNanoseconds: 1
        )
        let listModel = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [file]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(file)),
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        await noteModel.load(file: file, writeBlock: nil)
        noteModel.updateDraft("unsaved after failure")
        await waitForDetailNoteSave(noteModel)
        if let failedFileID = noteModel.failedDraftFileIDLeaving(fileID: file.id) {
            listModel.showUnsavedNoteDraftPreserved(fileID: failedFileID)
        }

        XCTAssertEqual(listModel.statusBanner, .unsavedNoteDraftPreserved(fileID: file.id))
    }

    @MainActor
    func testS114C114ReadOnlyAndMissingFilesDisableWritesWithoutClearingExistingNote() async {
        let missingFile = FileEntrySnapshot.detailMetaFixture(
            id: 116,
            currentName: "missing.pdf",
            availability: .missing
        )
        let noteStore = DetailNoteRecordingStore(readResults: [.success("existing note")])
        let model = DetailNoteModel(
            repoPath: "/tmp/repo",
            noteStore: noteStore,
            errorMapper: DetailMetaErrorMapper(mapping: .detailNoteIo()),
            debounceNanoseconds: 1
        )

        await model.load(file: missingFile, writeBlock: .fileMissing)
        model.updateDraft("should not write")
        let writes = await noteStore.recordedWriteRequests()

        XCTAssertEqual(model.state, .editing(
            fileID: missingFile.id,
            content: "existing note",
            saveStatus: .saved,
            writeBlock: .fileMissing
        ))
        XCTAssertEqual(writes, [])
    }

    @MainActor
    func testS114C114MainListMapsReadOnlyAndMissingWriteBlocks() async {
        let available = FileEntrySnapshot.detailMetaFixture(id: 117, currentName: "available.pdf")
        let missing = FileEntrySnapshot.detailMetaFixture(id: 118, currentName: "missing.pdf", availability: .missing)
        let model = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [available, missing], isReadOnly: true),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(available)),
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        XCTAssertEqual(model.noteWriteBlock(for: available), .repoReadOnly)

        let writableModel = MainFileListModel(
            opening: .detailMetaFixture(repoPath: "/tmp/repo", files: [missing]),
            fileLister: DetailMetaNoopLister(),
            fileDetailer: DetailMetaImmediateDetailer(result: .success(missing)),
            errorMapper: DetailMetaErrorMapper(mapping: .detailMetaFileNotFound())
        )

        XCTAssertEqual(writableModel.noteWriteBlock(for: missing), .fileMissing)
    }

    @MainActor
    func testS114C114WatcherIgnoresInFlightNoteSidecarWrite() async {
        let repoPath = "/tmp/repo"
        let relativePath = "docs/contracts/note.pdf.md"
        let absolutePath = "\(repoPath)/\(relativePath)"
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagItemCreated)
        let signal = MainExternalCreatedFileWatcher.signal(
            repoPath: repoPath,
            absolutePath: absolutePath,
            flags: flags,
            eventID: 9_114
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

    func testS114C114DefaultCoreBridgeReadsAndWritesRealSidecarNote() async throws {
        let repoURL = try makeDetailNoteTemporaryRepositoryURL()
        let sourceRoot = try makeDetailNoteTemporaryRepositoryURL()
        defer {
            try? FileManager.default.removeItem(at: repoURL)
            try? FileManager.default.removeItem(at: sourceRoot)
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

private struct DetailNoteReadRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

private struct DetailNoteWriteRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var contentMarkdown: String
}

private actor DetailNoteRecordingStore: CoreNoteReadingWriting {
    typealias ReadResult = Result<String?, Error>
    typealias WriteResult = Result<Void, Error>

    private var readResults: [ReadResult]
    private var writeResults: [WriteResult]
    private var reads: [DetailNoteReadRequest] = []
    private var writes: [DetailNoteWriteRequest] = []

    init(readResults: [ReadResult] = [], writeResults: [WriteResult] = []) {
        self.readResults = readResults
        self.writeResults = writeResults
    }

    func readNote(repoPath: String, fileID: Int64) async throws -> String? {
        reads.append(DetailNoteReadRequest(repoPath: repoPath, fileID: fileID))
        guard !readResults.isEmpty else { return nil }
        return try readResults.removeFirst().get()
    }

    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws {
        writes.append(DetailNoteWriteRequest(
            repoPath: repoPath,
            fileID: fileID,
            contentMarkdown: contentMarkdown
        ))
        guard !writeResults.isEmpty else { return }
        try writeResults.removeFirst().get()
    }

    func recordedReadRequests() -> [DetailNoteReadRequest] { reads }
    func recordedWriteRequests() -> [DetailNoteWriteRequest] { writes }
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

    func recordedMarks() -> [DetailNoteInFlightRequest] { marks }
    func recordedUnmarks() -> [DetailNoteInFlightRequest] { unmarks }
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

extension CoreErrorMappingSnapshot {
    static func detailNoteIo() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .io,
            userMessage: "无法保存笔记",
            severity: .medium,
            suggestedAction: "请确认资料库可写，然后重试。",
            recoverability: .retryable,
            rawContext: "S1-14 C1-14 write_note"
        )
    }
}

@MainActor
private func waitForDetailNoteSave(_ model: DetailNoteModel) async {
    for _ in 0..<200 {
        if model.state.saveStatus == .saved || model.state.saveStatus?.failedError != nil {
            return
        }
        await Task.yield()
    }
}

private func makeDetailNoteTemporaryRepositoryURL() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("AreaMatrixDetailNoteTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
