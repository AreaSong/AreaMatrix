import Foundation

extension ImportResultRouteState {
    init(
        sourceOpening: RepositoryOpeningResult,
        interruptedSession session: ImportBatchSessionSnapshot
    ) {
        self.init(sourceOpening: sourceOpening, progress: session.interruptedProgressSnapshot)
        shouldClearInterruptedSessionOnDone = true
    }

    var retryButtonTitle: String {
        isRetryingFailedItems ? "Retrying..." : "Retry Failed"
    }

    var exportDetailsText: String {
        var lines = [
            "AreaMatrix Import Result",
            summaryText,
            "No user file contents are included.",
            ""
        ]
        lines.append(contentsOf: items.map(exportLine(for:)))
        return lines.joined(separator: "\n")
    }

    private func exportLine(for item: Item) -> String {
        [
            item.status.rawValue,
            item.sanitizedTargetPath,
            item.reason,
            "source \(item.sanitizedSourcePath)",
            item.existingRelativePath.map { "existing \(Self.sanitizedPathDisplay($0))" }
        ].compactMap { $0 }.joined(separator: " | ")
    }

    func replacing(isRetryingFailedItems: Bool) -> ImportResultRouteState {
        ImportResultRouteState(
            sourceOpening: sourceOpening,
            imported: imported,
            failed: failed,
            stopped: stopped,
            pending: pending,
            currentPath: currentPath,
            items: items,
            isRetryingFailedItems: isRetryingFailedItems,
            changeLog: changeLog,
            exportState: exportState,
            shouldClearInterruptedSessionOnDone: shouldClearInterruptedSessionOnDone
        )
    }

    func replacing(changeLog: ChangeLogState) -> ImportResultRouteState {
        ImportResultRouteState(
            sourceOpening: sourceOpening,
            imported: imported,
            failed: failed,
            stopped: stopped,
            pending: pending,
            currentPath: currentPath,
            items: items,
            isRetryingFailedItems: isRetryingFailedItems,
            changeLog: changeLog,
            exportState: exportState,
            shouldClearInterruptedSessionOnDone: shouldClearInterruptedSessionOnDone
        )
    }

    func replacing(exportState: ExportState) -> ImportResultRouteState {
        ImportResultRouteState(
            sourceOpening: sourceOpening,
            imported: imported,
            failed: failed,
            stopped: stopped,
            pending: pending,
            currentPath: currentPath,
            items: items,
            isRetryingFailedItems: isRetryingFailedItems,
            changeLog: changeLog,
            exportState: exportState,
            shouldClearInterruptedSessionOnDone: shouldClearInterruptedSessionOnDone
        )
    }

    func markingImported(_ item: Item, entry: FileEntrySnapshot) -> ImportResultRouteState {
        replacingItem(
            matching: item,
            with: Item(
                fileID: entry.id,
                sourcePath: item.sourcePath,
                targetPath: entry.path,
                status: .imported,
                reason: "-",
                retryContext: nil,
                existingRelativePath: nil
            ),
            importedDelta: 1,
            failedDelta: -1
        )
    }

    func markingFailed(_ item: Item, message: String) -> ImportResultRouteState {
        replacingItem(
            matching: item,
            with: Item(
                fileID: item.fileID,
                sourcePath: item.sourcePath,
                targetPath: item.targetPath,
                status: .failed,
                reason: message,
                retryContext: item.retryContext,
                existingRelativePath: item.existingRelativePath
            ),
            importedDelta: 0,
            failedDelta: 0
        )
    }

    private func replacingItem(
        matching item: Item,
        with replacement: Item,
        importedDelta: Int,
        failedDelta: Int
    ) -> ImportResultRouteState {
        var updatedItems = items
        guard let index = updatedItems.firstIndex(where: { $0.id == item.id }) else { return self }
        updatedItems[index] = replacement
        return ImportResultRouteState(
            sourceOpening: sourceOpening,
            imported: max(0, imported + importedDelta),
            failed: max(0, failed + failedDelta),
            stopped: stopped,
            pending: pending,
            currentPath: replacement.targetPath,
            items: updatedItems,
            isRetryingFailedItems: isRetryingFailedItems,
            changeLog: changeLog,
            exportState: exportState,
            shouldClearInterruptedSessionOnDone: shouldClearInterruptedSessionOnDone
        )
    }
}

extension RepositoryOpeningResult {
    func focusingImportResultItem(_ item: ImportResultRouteState.Item) -> RepositoryOpeningResult {
        guard let fileID = item.fileID else { return self }
        var opening = self
        if !opening.currentCategoryFiles.contains(where: { $0.id == fileID }) {
            opening.currentCategoryFiles.insert(item.focusFileSnapshot, at: 0)
        }
        return opening
    }
}

private extension ImportResultRouteState.Item {
    var focusFileSnapshot: FileEntrySnapshot {
        FileEntrySnapshot(
            id: fileID ?? -1,
            path: targetPath,
            originalName: displayName,
            currentName: displayName,
            category: category,
            sizeBytes: 0,
            hashSha256: "import-result-\(fileID ?? -1)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: sourcePath,
            importedAt: 0,
            updatedAt: 0
        )
    }

    var displayName: String {
        let name = (targetPath as NSString).lastPathComponent
        return name.isEmpty ? targetPath : name
    }

    var category: String {
        let category = (targetPath as NSString).deletingLastPathComponent
        return category.isEmpty || category == "." ? "inbox" : category
    }
}
