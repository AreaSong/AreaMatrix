import Foundation

extension ImportResultRouteState {
    var retryButtonTitle: String {
        isRetryingFailedItems ? "Retrying..." : "Retry Failed"
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
            changeLog: changeLog
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
            changeLog: changeLog
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
                retryContext: nil
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
                retryContext: item.retryContext
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
            changeLog: changeLog
        )
    }
}
