import Foundation

extension ImportResultRouteState {
    var retryButtonTitle: String {
        isRetryingFailedItems ? "Retrying..." : "Retry Failed"
    }

    var exportDetailsText: String {
        var lines = [
            "AreaMatrix Import Result",
            summaryText,
            "No user file contents are included.",
            "",
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
            item.existingRelativePath.map { "existing \(Self.sanitizedPathDisplay($0))" },
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
            exportState: exportState
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
            exportState: exportState
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
            exportState: exportState
        )
    }

    func markingImported(_ item: Item, entry: FileEntrySnapshot) -> ImportResultRouteState {
        replacingItem(
            matching: item,
            with: Item(
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
            exportState: exportState
        )
    }
}
