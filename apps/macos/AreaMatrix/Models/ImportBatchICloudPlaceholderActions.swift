import Foundation

extension ImportBatchCopyImportModel {
    func downloadICloudPlaceholderAndRetry(rowID: ImportBatchCopyImportRow.ID) async -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        guard case let .iCloudPlaceholder(path, _) = row.status else { return false }
        isICloudDownloading = true
        defer { isICloudDownloading = false }

        do {
            try await placeholderDownloader.downloadPlaceholder(at: row.sourceURL)
            setStatus(.loading, for: rowID)
            return true
        } catch {
            setStatus(.iCloudPlaceholder(
                path: path,
                message: "iCloud 下载失败：\(error.localizedDescription)"
            ), for: rowID)
            return false
        }
    }

    func downloadAllICloudPlaceholdersAndRetry() async -> Bool {
        var didDownload = false
        for row in rows {
            if case .iCloudPlaceholder = row.status {
                didDownload = await downloadICloudPlaceholderAndRetry(rowID: row.id) || didDownload
            }
        }
        return didDownload
    }

    func markICloudPlaceholderPending(rowID: ImportBatchCopyImportRow.ID) {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        guard case let .iCloudPlaceholder(path, _) = row.status else { return }
        setStatus(.skippedICloud(path: path), for: rowID)
    }
}
