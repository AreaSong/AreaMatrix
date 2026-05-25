import Foundation

struct ImportBatchSessionSnapshot: Equatable {
    var repoPath: String
    var storageMode: ImportSingleFileStorageMode
    var completed: Int
    var failed: Int
    var total: Int
    var currentPath: String
    var items: [ImportBatchProgressSnapshot.Item]

    var isUnfinishedCopySession: Bool {
        storageMode == .copy && completed + failed < total
    }

    var progressSnapshot: ImportBatchProgressSnapshot {
        ImportBatchProgressSnapshot(
            completed: completed,
            failed: failed,
            total: total,
            remaining: max(total - completed - failed, 0),
            currentPath: currentPath,
            items: items
        )
    }
}

protocol ImportBatchSessionPersisting {
    func saveSession(_ session: ImportBatchSessionSnapshot) async
    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot?
    func clearSession(repoPath: String) async
}

struct FileImportBatchSessionStore: ImportBatchSessionPersisting {
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func saveSession(_ session: ImportBatchSessionSnapshot) async {
        do {
            try write(session)
        } catch {
            // Import recovery metadata must never block the user file operation.
        }
    }

    func loadSession(repoPath: String) async -> ImportBatchSessionSnapshot? {
        do {
            let data = try Data(contentsOf: sessionURL(repoPath: repoPath))
            return try decoder.decode(CodableImportBatchSession.self, from: data).snapshot
        } catch {
            return nil
        }
    }

    func clearSession(repoPath: String) async {
        do {
            try fileManager.removeItem(at: sessionURL(repoPath: repoPath))
        } catch {
            // Missing or already-clean session files are acceptable.
        }
    }

    private func write(_ session: ImportBatchSessionSnapshot) throws {
        let url = sessionURL(repoPath: session.repoPath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(CodableImportBatchSession(snapshot: session))
        try data.write(to: url, options: .atomic)
    }

    private func sessionURL(repoPath: String) -> URL {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(".areamatrix", isDirectory: true)
            .appendingPathComponent("import-sessions", isDirectory: true)
            .appendingPathComponent("current.json")
    }
}

private struct CodableImportBatchSession: Codable {
    var repoPath: String
    var storageMode: ImportSingleFileStorageMode
    var completed: Int
    var failed: Int
    var total: Int
    var currentPath: String
    var items: [CodableImportBatchSessionItem]

    init(snapshot: ImportBatchSessionSnapshot) {
        repoPath = snapshot.repoPath
        storageMode = snapshot.storageMode
        completed = snapshot.completed
        failed = snapshot.failed
        total = snapshot.total
        currentPath = snapshot.currentPath
        items = snapshot.items.map(CodableImportBatchSessionItem.init(item:))
    }

    var snapshot: ImportBatchSessionSnapshot {
        ImportBatchSessionSnapshot(
            repoPath: repoPath,
            storageMode: storageMode,
            completed: completed,
            failed: failed,
            total: total,
            currentPath: currentPath,
            items: items.map(\.snapshotItem)
        )
    }
}

private struct CodableImportBatchSessionItem: Codable {
    var sourcePath: String
    var fileID: Int64?
    var targetPath: String
    var phase: ImportBatchProgressSnapshot.Phase
    var errorMessage: String?
    var existingRelativePath: String?
    var importConflictBatch: ImportConflictBatchProgressMetadata?

    init(item: ImportBatchProgressSnapshot.Item) {
        sourcePath = item.sourcePath
        fileID = item.fileID
        targetPath = item.targetPath
        phase = item.phase
        errorMessage = item.errorMessage
        existingRelativePath = item.existingRelativePath
        importConflictBatch = item.importConflictBatch
    }

    var snapshotItem: ImportBatchProgressSnapshot.Item {
        ImportBatchProgressSnapshot.Item(
            fileID: fileID,
            sourcePath: sourcePath,
            targetPath: targetPath,
            phase: phase,
            errorMessage: errorMessage,
            existingRelativePath: existingRelativePath,
            importConflictBatch: importConflictBatch
        )
    }
}

extension ImportBatchSessionSnapshot {
    var interruptedProgressSnapshot: ImportBatchProgressSnapshot {
        let resolvedItems = items.map { item in
            guard item.phase != .done, item.phase != .failed else { return item }
            var pendingItem = item
            pendingItem.phase = .pending
            pendingItem.errorMessage = "Import not completed before AreaMatrix quit"
            return pendingItem
        }
        return ImportBatchProgressSnapshot(
            completed: completed,
            failed: failed,
            total: total,
            remaining: max(total - completed - failed, 0),
            currentPath: currentPath,
            items: resolvedItems
        )
    }
}
