import Foundation

protocol CoreFileDeleting: Sendable {
    func deleteFile(repoPath: String, fileID: Int64) async throws
    func removeIndexEntry(repoPath: String, fileID: Int64) async throws
}

extension CoreBridge: CoreFileDeleting {
    func deleteFile(repoPath: String, fileID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try deleteCoreFile(repoPath: repoPath, fileID: fileID)
        }.value
    }

    func removeIndexEntry(repoPath: String, fileID: Int64) async throws {
        try await Task.detached(priority: .userInitiated) {
            try removeCoreIndexEntry(repoPath: repoPath, fileID: fileID)
        }.value
    }
}

private func deleteCoreFile(repoPath: String, fileID: Int64) throws {
    try deleteFile(repoPath: repoPath, fileId: fileID)
}

private func removeCoreIndexEntry(repoPath: String, fileID: Int64) throws {
    try removeIndexEntry(repoPath: repoPath, fileId: fileID)
}
