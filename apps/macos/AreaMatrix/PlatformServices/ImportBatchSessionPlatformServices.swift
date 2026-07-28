import Foundation

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
    var importCommitState: CoreImportCommitState
    var failure: ImportBatchSessionFailureDescriptor?
    var existingRelativePath: String?
    var importConflictBatch: ImportConflictBatchProgressMetadata?

    init(item: ImportBatchProgressSnapshot.Item) {
        sourcePath = item.sourcePath
        fileID = item.fileID
        targetPath = item.targetPath
        phase = item.phase
        importCommitState = item.importCommitState
        failure = item.errorDisplayText.map(ImportBatchSessionFailureDescriptor.init(displayText:))
        existingRelativePath = item.existingRelativePath
        importConflictBatch = item.importConflictBatch
    }

    var snapshotItem: ImportBatchProgressSnapshot.Item {
        ImportBatchProgressSnapshot.Item(
            fileID: fileID,
            sourcePath: sourcePath,
            targetPath: targetPath,
            phase: phase,
            importCommitState: importCommitState,
            errorDisplayText: failure?.displayText,
            existingRelativePath: existingRelativePath,
            importConflictBatch: importConflictBatch
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath
        case fileID
        case targetPath
        case phase
        case importCommitState
        case failure
        case errorDisplayText
        case errorMessage
        case existingRelativePath
        case importConflictBatch
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        fileID = try container.decodeIfPresent(Int64.self, forKey: .fileID)
        targetPath = try container.decode(String.self, forKey: .targetPath)
        phase = try container.decode(ImportBatchProgressSnapshot.Phase.self, forKey: .phase)
        importCommitState = try container.decodeIfPresent(
            CoreImportCommitState.self,
            forKey: .importCommitState
        ) ?? .committed
        failure = try container.decodeIfPresent(ImportBatchSessionFailureDescriptor.self, forKey: .failure)
            ?? Self.legacyFailure(from: container)
        existingRelativePath = try container.decodeIfPresent(String.self, forKey: .existingRelativePath)
        importConflictBatch = try container.decodeIfPresent(
            ImportConflictBatchProgressMetadata.self,
            forKey: .importConflictBatch
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encodeIfPresent(fileID, forKey: .fileID)
        try container.encode(targetPath, forKey: .targetPath)
        try container.encode(phase, forKey: .phase)
        try container.encode(importCommitState, forKey: .importCommitState)
        try container.encodeIfPresent(failure, forKey: .failure)
        try container.encodeIfPresent(existingRelativePath, forKey: .existingRelativePath)
        try container.encodeIfPresent(importConflictBatch, forKey: .importConflictBatch)
    }

    private static func legacyFailure(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> ImportBatchSessionFailureDescriptor? {
        if let legacy = try? container.decodeIfPresent(AppDisplayText.self, forKey: .errorDisplayText) {
            return ImportBatchSessionFailureDescriptor(displayText: legacy)
        }
        if let legacy = try? container.decodeIfPresent(String.self, forKey: .errorMessage) {
            return ImportBatchSessionFailureDescriptor(code: .technicalDetail, technicalDetail: legacy)
        }
        return nil
    }
}
