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

extension ImportBatchSessionSnapshot {
    var interruptedProgressSnapshot: ImportBatchProgressSnapshot {
        let resolvedItems = items.map { item in
            guard item.phase != .done, item.phase != .failed else { return item }
            var pendingItem = item
            pendingItem.phase = .pending
            pendingItem.errorMessage = L10n.string("Import not completed before AreaMatrix quit")
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
