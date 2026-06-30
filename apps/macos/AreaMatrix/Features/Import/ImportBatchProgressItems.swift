struct ImportConflictBatchRoute: Equatable {
    var importSessionID: String
    var conflictIDs: [String]
    var source: CommandPaletteLinkedPageRoute?
}

struct ImportConflictBatchProgressMetadata: Codable, Equatable {
    var importSessionID: String
    var conflictID: String
}

extension ImportConflictBatchProgressMetadata {
    init?(importSessionID: String?, conflictID: String?) {
        let session = importSessionID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let conflict = conflictID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !session.isEmpty, !conflict.isEmpty else { return nil }
        self.importSessionID = session
        self.conflictID = conflict
    }
}

extension ImportConflictBatchRoute {
    init?(metadata: [ImportConflictBatchProgressMetadata], source: CommandPaletteLinkedPageRoute?) {
        guard let importSessionID = metadata.first?.importSessionID else { return nil }
        var conflictIDs: [String] = []
        for item in metadata where item.importSessionID == importSessionID && !conflictIDs.contains(item.conflictID) {
            conflictIDs.append(item.conflictID)
        }
        guard !conflictIDs.isEmpty else { return nil }
        self.importSessionID = importSessionID
        self.conflictIDs = conflictIDs
        self.source = source
    }
}

@MainActor
extension ImportBatchCopyImportModel {
    func progressItems() -> [ImportBatchProgressSnapshot.Item] {
        rows.map { row in
            ImportBatchProgressSnapshot.Item(
                sourcePath: row.sourcePath,
                targetPath: targetRelativePath(for: row, destination: selectedDestination),
                phase: Self.progressPhase(for: row.status),
                errorMessage: Self.progressErrorMessage(for: row.status),
                existingRelativePath: row.existingConflictPath,
                importConflictBatch: importConflictBatchMetadata(for: row)
            )
        }
    }

    private func importConflictBatchMetadata(
        for row: ImportBatchCopyImportRow
    ) -> ImportConflictBatchProgressMetadata? {
        guard let importSessionID = normalizedImportConflictBatchSessionID,
              let conflictID = request?.importConflictID(forSourcePath: row.sourcePath) else { return nil }
        return ImportConflictBatchProgressMetadata(
            importSessionID: importSessionID,
            conflictID: conflictID
        )
    }

    private static func progressPhase(
        for status: ImportBatchCopyImportRowStatus
    ) -> ImportBatchProgressSnapshot.Phase {
        switch status {
        case let .importing(mode):
            mode.importProgressPhase
        case .imported:
            .done
        case .error:
            .failed
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked,
             .skippedDuplicate, .skippedICloud:
            .pending
        }
    }

    private static func progressErrorMessage(for status: ImportBatchCopyImportRowStatus) -> String? {
        guard case let .error(message) = status else { return nil }
        return message
    }
}

private extension ImportSingleFileStorageMode {
    var importProgressPhase: ImportBatchProgressSnapshot.Phase {
        switch self {
        case .copy:
            .copying
        case .move:
            .moving
        case .indexOnly:
            .writingIndex
        }
    }
}
