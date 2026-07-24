import Foundation

protocol CoreFileRenaming: Sendable {
    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot
}

protocol CoreBatchRenaming: Sendable {
    func previewBatchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) async throws -> BatchRenamePreviewReportSnapshot

    func batchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        previewToken: String
    ) async throws -> BatchRenameReportSnapshot
}

extension CoreBridge: CoreFileRenaming, CoreBatchRenaming {
    func renameFile(repoPath: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        let contentLocale = try await repositoryContentLocaleSnapshot(repoPath: repoPath)
        let entry = try await Task.detached(priority: .userInitiated) {
            try renameCoreFile(
                repoPath: repoPath,
                fileID: fileID,
                newName: newName,
                contentLocale: contentLocale
            )
        }.value
        return await makeFileEntrySnapshot(from: entry, repoPath: repoPath)
    }

    func previewBatchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot
    ) async throws -> BatchRenamePreviewReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try BatchRenamePreviewReportSnapshot(coreReport: AreaMatrix.previewBatchRename(
                repoPath: repoPath,
                fileIds: fileIDs,
                rule: BatchRenameRule(rule)
            ))
        }.value
    }

    func batchRename(
        repoPath: String,
        fileIDs: [Int64],
        rule: BatchRenameRuleSnapshot,
        previewToken: String
    ) async throws -> BatchRenameReportSnapshot {
        let report = try await Task.detached(priority: .userInitiated) {
            try AreaMatrix.batchRename(
                repoPath: repoPath,
                fileIds: fileIDs,
                rule: BatchRenameRule(rule),
                previewToken: previewToken
            )
        }.value
        let updatedFiles = await makeFileEntrySnapshots(from: report.updatedFiles, repoPath: repoPath)
        return BatchRenameReportSnapshot(coreReport: report, updatedFiles: updatedFiles)
    }
}

private func renameCoreFile(
    repoPath: String,
    fileID: Int64,
    newName: String,
    contentLocale: String
) throws -> FileEntry {
    try renameFile(
        repoPath: repoPath,
        fileId: fileID,
        newName: newName,
        contentLocale: ContentLocale(snapshotValue: contentLocale)
    )
}

extension BatchRenamePreviewReportSnapshot {
    init(coreReport: BatchRenamePreviewReport) {
        requestedFileCount = coreReport.requestedFileCount
        rule = BatchRenameRuleSnapshot(coreRule: coreReport.rule)
        previewToken = coreReport.previewToken
        willRenameCount = coreReport.willRenameCount
        displayOnlyCount = coreReport.displayOnlyCount
        unchangedCount = coreReport.unchangedCount
        blockedCount = coreReport.blockedCount
        conflictCount = coreReport.conflictCount
        items = coreReport.items.map(BatchRenamePreviewItemSnapshot.init)
        canApply = coreReport.canApply
        applyBlockedReason = coreReport.applyBlockedReason
    }
}

extension BatchRenameReportSnapshot {
    init(coreReport: BatchRenameReport, updatedFiles: [FileEntrySnapshot]) {
        requestedFileCount = coreReport.requestedFileCount
        renamedCount = coreReport.renamedCount
        displayNameUpdatedCount = coreReport.displayNameUpdatedCount
        unchangedCount = coreReport.unchangedCount
        skippedCount = coreReport.skippedCount
        failedCount = coreReport.failedCount
        itemResults = coreReport.itemResults.map(BatchRenameItemResultSnapshot.init)
        self.updatedFiles = updatedFiles
        undoToken = coreReport.undoToken
    }
}

private extension BatchRenameRule {
    init(_ snapshot: BatchRenameRuleSnapshot) {
        self.init(
            mode: BatchRenameMode(snapshot.mode),
            prefix: snapshot.prefix,
            dateSource: snapshot.dateSource.map(BatchRenameDateSource.init),
            dateFormat: snapshot.dateFormat,
            separator: snapshot.separator,
            startNumber: snapshot.startNumber,
            padding: snapshot.padding,
            find: snapshot.find,
            replacement: snapshot.replacement,
            caseSensitive: snapshot.caseSensitive
        )
    }
}

private extension BatchRenameMode {
    init(_ snapshot: BatchRenameModeSnapshot) {
        switch snapshot {
        case .prefix: self = .prefix
        case .datePrefix: self = .datePrefix
        case .keepBaseSequence: self = .keepBaseSequence
        case .replaceText: self = .replaceText
        }
    }
}

private extension BatchRenameDateSource {
    init(_ snapshot: BatchRenameDateSourceSnapshot) {
        switch snapshot {
        case .imported: self = .imported
        case .modified: self = .modified
        case .today: self = .today
        }
    }
}

extension CoreBridge {
    func makeFileEntrySnapshots(from entries: [FileEntry], repoPath: String) async -> [FileEntrySnapshot] {
        var snapshots: [FileEntrySnapshot] = []
        for entry in entries {
            await snapshots.append(makeFileEntrySnapshot(from: entry, repoPath: repoPath))
        }
        return snapshots
    }
}
