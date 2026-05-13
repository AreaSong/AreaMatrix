import Foundation

protocol CoreNoteReadingWriting: Sendable {
    func readNote(repoPath: String, fileID: Int64) async throws -> String?
    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws
}

extension CoreBridge: CoreNoteReadingWriting {
    func readNote(repoPath: String, fileID: Int64) async throws -> String? {
        try await Task.detached(priority: .userInitiated) {
            try readCoreNote(repoPath: repoPath, fileID: fileID)
        }.value
    }

    func writeNote(repoPath: String, fileID: Int64, contentMarkdown: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try writeCoreNote(repoPath: repoPath, fileID: fileID, contentMarkdown: contentMarkdown)
        }.value
    }
}

private func readCoreNote(repoPath: String, fileID: Int64) throws -> String? {
    try readNote(repoPath: repoPath, fileId: fileID)
}

private func writeCoreNote(repoPath: String, fileID: Int64, contentMarkdown: String) throws {
    try writeNote(repoPath: repoPath, fileId: fileID, contentMd: contentMarkdown)
}
