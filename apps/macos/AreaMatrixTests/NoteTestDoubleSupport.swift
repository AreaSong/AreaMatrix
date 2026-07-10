@testable import AreaMatrix

struct NoopNoteStore: CoreNoteReadingWriting {
    func readNote(repoPath _: String, fileID _: Int64) async throws -> String? {
        nil
    }

    func writeNote(repoPath _: String, fileID _: Int64, contentMarkdown _: String) async throws {}
}

struct NoteReadRequest: Equatable {
    var repoPath: String
    var fileID: Int64
}

struct NoteWriteRequest: Equatable {
    var repoPath: String
    var fileID: Int64
    var contentMarkdown: String
}

actor RecordingNoteStore: CoreNoteReadingWriting {
    typealias ReadResult = Swift.Result<String?, Error>
    typealias WriteResult = Swift.Result<Void, Error>

    private var readResults: [ReadResult]
    private var writeResults: [WriteResult]
    private var reads: [NoteReadRequest] = []
    private var writes: [NoteWriteRequest] = []

    init(readResults: [ReadResult] = [], writeResults: [WriteResult] = []) {
        self.readResults = readResults
        self.writeResults = writeResults
    }

    func readNote(repoPath: String, fileID: Int64) async throws -> String? {
        reads.append(NoteReadRequest(repoPath: repoPath, fileID: fileID))
        guard !readResults.isEmpty else { return nil }
        return try readResults.removeFirst().get()
    }

    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws {
        writes.append(NoteWriteRequest(
            repoPath: repoPath,
            fileID: fileID,
            contentMarkdown: contentMarkdown
        ))
        guard !writeResults.isEmpty else { return }
        try writeResults.removeFirst().get()
    }

    func recordedReadRequests() -> [NoteReadRequest] {
        reads
    }

    func recordedWriteRequests() -> [NoteWriteRequest] {
        writes
    }
}

typealias DetailNoteReadRequest = NoteReadRequest
typealias DetailNoteWriteRequest = NoteWriteRequest
typealias DetailNoteRecordingStore = RecordingNoteStore

@MainActor
func makeDetailNoteTestModel(
    repoPath: String = "/tmp/repo",
    noteStore: any CoreNoteReadingWriting,
    errorMapper: (any CoreErrorMapping)? = nil,
    inFlightTracker: (any InFlightFileChangeTracking)? = nil,
    debounceNanoseconds: UInt64 = 1
) -> DetailNoteModel {
    DetailNoteModel(
        repoPath: repoPath,
        noteStore: noteStore,
        errorMapper: errorMapper ?? StaticCoreErrorMapper(mapping: .detailNoteIo()),
        inFlightTracker: inFlightTracker ?? InFlightFileChangeTracker.shared,
        debounceNanoseconds: debounceNanoseconds
    )
}

@discardableResult
@MainActor
func waitForDetailNoteSaveStatus(
    _ model: DetailNoteModel,
    matching predicate: (MainDetailNoteSaveStatus?) -> Bool,
    attempts: Int = 200,
    delayNanoseconds: UInt64? = nil,
    failureMessage: @escaping () -> String,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainDetailNoteSaveStatus? {
    await waitForMainActorTestValue(
        attempts: attempts,
        delayNanoseconds: delayNanoseconds,
        failureMessage: failureMessage,
        file: file,
        line: line,
        value: {
            let status = model.state.saveStatus
            return predicate(status) ? status : nil
        }
    )
}

@discardableResult
@MainActor
func waitForDetailNoteSaveSettled(
    _ model: DetailNoteModel,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainDetailNoteSaveStatus? {
    await waitForDetailNoteSaveStatus(
        model,
        matching: { $0 == .saved || $0?.failedError != nil },
        failureMessage: { "Timed out waiting for detail note save to finish" },
        file: file,
        line: line
    )
}

@discardableResult
@MainActor
func waitForDetailNoteSaved(
    _ model: DetailNoteModel,
    delayNanoseconds: UInt64? = 5_000_000,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> MainDetailNoteSaveStatus? {
    await waitForDetailNoteSaveStatus(
        model,
        matching: { $0 == .saved },
        delayNanoseconds: delayNanoseconds,
        failureMessage: { "Timed out waiting for detail note save" },
        file: file,
        line: line
    )
}

extension CoreErrorMappingSnapshot {
    static func detailNoteIo() -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot.testFixture(
            kind: .io,
            userMessage: "无法保存笔记",
            severity: .medium,
            suggestedAction: "请确认资料库可写，然后重试。",
            recoverability: .retryable,
            rawContext: "detail-note note-sidecar write_note"
        )
    }
}
