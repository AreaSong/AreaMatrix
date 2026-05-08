import Foundation

protocol CoreFileRenaming: Sendable {
    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot
}

extension CoreBridge: CoreFileRenaming {
    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        let entry = try await Task.detached(priority: .userInitiated) {
            try renameCoreFile(repoPath: repoPath, fileID: fileID, newName: newName)
        }.value
        return await makeFileEntrySnapshot(from: entry, repoPath: repoPath)
    }
}

private func renameCoreFile(repoPath: String, fileID: Int64, newName: String) throws -> FileEntry {
    try renameFile(repoPath: repoPath, fileId: fileID, newName: newName)
}
