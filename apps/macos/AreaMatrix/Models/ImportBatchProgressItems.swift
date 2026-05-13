import Foundation

@MainActor
extension ImportBatchCopyImportModel {
    func progressItems() -> [ImportBatchProgressSnapshot.Item] {
        rows.map { row in
            ImportBatchProgressSnapshot.Item(
                sourcePath: row.sourcePath,
                targetPath: targetRelativePath(for: row, destination: selectedDestination),
                phase: Self.progressPhase(for: row.status),
                errorMessage: Self.progressErrorMessage(for: row.status),
                existingRelativePath: row.existingConflictPath
            )
        }
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
