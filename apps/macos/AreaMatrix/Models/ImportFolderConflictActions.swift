import Foundation

protocol ImportFolderConflictPrechecking: Sendable {
    func precheckFolderConflicts(
        repoPath: String,
        rows: [ImportFolderPreviewRow],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportFolderConflictPrecheckResult]
}

enum ImportFolderConflictPrecheckResult: Equatable, Sendable {
    case duplicate(existingPath: String)
    case nameConflict(existingPath: String)
    case blocked(String)
}

struct CoreImportFolderConflictPrechecker: ImportFolderConflictPrechecking {
    private let fileLoader: any ImportBatchCoreFileLoading

    init(fileLoader: any ImportBatchCoreFileLoading = CoreBridgeBatchFileLoader()) {
        self.fileLoader = fileLoader
    }

    func precheckFolderConflicts(
        repoPath: String,
        rows: [ImportFolderPreviewRow],
        destination: ImportBatchDestinationOption
    ) async -> [String: ImportFolderConflictPrecheckResult] {
        let candidates = rows.filter(\.status.canRunFolderConflictPrecheck)
        guard !candidates.isEmpty else { return [:] }

        do {
            let files = try await fileLoader.loadImportPreviewFiles(repoPath: repoPath, categories: [nil])
            return candidates.reduce(into: [:]) { results, row in
                results[row.id] = precheck(row: row, destination: destination, against: files)
            }
        } catch {
            return candidates.reduce(into: [:]) { results, row in
                results[row.id] = .blocked("Conflict precheck failed: \(error.localizedDescription)")
            }
        }
    }

    private func precheck(
        row: ImportFolderPreviewRow,
        destination: ImportBatchDestinationOption,
        against files: [FileEntrySnapshot]
    ) -> ImportFolderConflictPrecheckResult? {
        do {
            let sourceHash = try ImportSingleFileHasher.sha256Hex(for: row.fileURL)
            if let duplicate = files.first(where: { $0.hashSha256 == sourceHash }) {
                return .duplicate(existingPath: duplicate.path)
            }
            let targetPath = ImportFolderConflictTarget.relativePath(for: row, destination: destination)
            if let sameName = files.first(where: { $0.path == targetPath }) {
                return .nameConflict(existingPath: sameName.path)
            }
            return nil
        } catch {
            return .blocked("Conflict precheck failed: \(error.localizedDescription)")
        }
    }
}

enum ImportFolderConflictTarget {
    static func relativePath(
        for row: ImportFolderPreviewRow,
        destination: ImportBatchDestinationOption
    ) -> String {
        let filename = row.resolvedIncomingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category = category(for: row, destination: destination) else {
            return filename
        }
        return "\(category)/\(filename)"
    }

    static func category(
        for row: ImportFolderPreviewRow,
        destination: ImportBatchDestinationOption
    ) -> String? {
        switch destination {
        case .autoClassify:
            let category = row.predictedCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "inbox"
            return category.isEmpty ? "inbox" : category
        case .category(let slug):
            return slug.trimmingCharacters(in: .whitespacesAndNewlines)
        case .repositoryRoot:
            return nil
        }
    }
}

@MainActor
extension ImportFolderPreviewModel {
    func updateDuplicateStrategy(
        for rowID: ImportFolderPreviewRow.ID,
        strategy: ImportBatchDuplicateResolutionStrategy
    ) {
        guard canSelectDuplicateStrategy(strategy) else { return }
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case .duplicate(let existingPath, _, let isReplaceConfirmed) = row.status else { return }
        setRowStatus(.duplicate(
            existingPath: existingPath,
            strategy: strategy,
            isReplaceConfirmed: strategy == .replace ? isReplaceConfirmed : false
        ), for: rowID)
    }

    func updateNameConflictResolution(
        for rowID: ImportFolderPreviewRow.ID,
        resolution: ImportBatchNameConflictResolution
    ) {
        guard canSelectNameConflictResolution(resolution) else { return }
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case .nameConflict(let existingPath, _) = row.status else { return }
        setRowStatus(.nameConflict(existingPath: existingPath, resolution: resolution), for: rowID)
    }

    func renameIncomingFile(for rowID: ImportFolderPreviewRow.ID, to name: String) {
        updateNameConflictResolution(for: rowID, resolution: .renameIncoming(name))
    }

    func beginReplaceConfirmation(
        for rowID: ImportFolderPreviewRow.ID
    ) -> ImportSingleFileReplaceConfirmationContext? {
        clearReplaceConfirmationRecovery()
        guard let row = rows.first(where: { $0.id == rowID }) else { return nil }
        guard replaceOptionVisibility == .enabled else { return nil }
        guard let existingPath = row.existingConflictPath else { return nil }
        return ImportSingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: row.fileURL.path,
            incomingSizeBytes: row.sizeBytes,
            targetRelativePath: targetRelativePath(for: row),
            isTrashAvailable: true
        )
    }

    func applyReplaceConfirmation(
        for rowID: ImportFolderPreviewRow.ID,
        decision: ImportSingleFileReplaceConfirmationDecision
    ) -> Bool {
        guard decision.understandsReplace else {
            recordReplaceConfirmationFailure("Replace 需要先勾选二次确认")
            return false
        }
        guard let expected = currentReplaceConfirmationContext(for: rowID), expected == decision.context else {
            recordReplaceConfirmationFailure("Replace confirmation context expired")
            return false
        }
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }

        switch row.status {
        case .duplicate(let existingPath, .replace, _):
            setRowStatus(.duplicate(
                existingPath: existingPath,
                strategy: .replace,
                isReplaceConfirmed: true
            ), for: rowID)
        case .nameConflict(let existingPath, .replace):
            setRowStatus(.nameConflict(
                existingPath: existingPath,
                resolution: .replace(isConfirmed: true)
            ), for: rowID)
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .importing,
             .skippedDuplicate, .skippedICloud, .imported, .error:
            recordReplaceConfirmationFailure("Replace confirmation context expired")
            return false
        }
        clearReplaceConfirmationRecovery()
        return true
    }

    func markICloudPlaceholderPending(rowID: ImportFolderPreviewRow.ID) {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case .iCloudPlaceholder(let path) = row.status else { return }
        setRowStatus(.skippedICloud(path: path), for: rowID)
    }

    private func canSelectDuplicateStrategy(_ strategy: ImportBatchDuplicateResolutionStrategy) -> Bool {
        strategy != .replace || replaceOptionVisibility == .enabled
    }

    private func canSelectNameConflictResolution(_ resolution: ImportBatchNameConflictResolution) -> Bool {
        !resolution.isReplace || replaceOptionVisibility == .enabled
    }

    private func currentReplaceConfirmationContext(
        for rowID: ImportFolderPreviewRow.ID
    ) -> ImportSingleFileReplaceConfirmationContext? {
        guard let row = rows.first(where: { $0.id == rowID }) else { return nil }
        guard replaceOptionVisibility == .enabled else { return nil }
        guard let existingPath = row.existingConflictPath else { return nil }
        return ImportSingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: row.fileURL.path,
            incomingSizeBytes: row.sizeBytes,
            targetRelativePath: targetRelativePath(for: row),
            isTrashAvailable: true
        )
    }

}
