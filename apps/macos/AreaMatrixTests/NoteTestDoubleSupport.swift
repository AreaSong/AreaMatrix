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
