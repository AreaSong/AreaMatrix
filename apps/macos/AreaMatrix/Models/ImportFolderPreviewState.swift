import Foundation

protocol ImportFolderScanning: Sendable {
    func scanFolder(rootURL: URL, includeHiddenFiles: Bool, followSymlinks: Bool) async -> ImportFolderScanResult
}

struct ImportFolderScanResult: Equatable, Sendable {
    var rows: [ImportFolderPreviewRow]
    var folderCount: Int
    var skippedRules: [ImportFolderSkippedRule]
    var errors: [ImportFolderScanError]
}

enum ImportFolderPreviewStatus: Equatable, Sendable {
    case idle
    case scanning(path: String)
    case checkingConflicts
    case loaded(ready: Int, total: Int, failed: Int)
    case empty
    case failed(String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        if case .checkingConflicts = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .scanning(let path):
            return "正在预扫描 \(path)"
        case .checkingConflicts:
            return "Checking conflicts..."
        case .loaded(let ready, let total, let failed):
            if failed == 0 {
                return "已完成 \(total) 个文件的分类预览"
            }
            return "已完成 \(ready)/\(total) 个文件的分类预览，\(failed) 个失败"
        case .empty:
            return "没有可导入文件"
        case .failed(let message):
            return message
        }
    }
}

enum ImportFolderPreviewRowStatus: Equatable, Sendable {
    case loading
    case ready(reasonLabel: String)
    case duplicate(
        existingPath: String,
        strategy: ImportBatchDuplicateResolutionStrategy,
        isReplaceConfirmed: Bool
    )
    case nameConflict(existingPath: String, resolution: ImportBatchNameConflictResolution)
    case iCloudPlaceholder(path: String)
    case blocked(String)
    case importing(ImportSingleFileStorageMode)
    case skippedDuplicate(existingPath: String)
    case skippedICloud(path: String)
    case imported(ImportSingleFileStorageMode)
    case error(String)

    var tag: String {
        switch self {
        case .loading:
            return "PREVIEW"
        case .ready:
            return "OK"
        case .duplicate:
            return "DUP"
        case .nameConflict:
            return "NAME"
        case .iCloudPlaceholder:
            return "ICLOUD"
        case .blocked:
            return "BLOCKED"
        case .importing:
            return "IMPORTING"
        case .skippedDuplicate:
            return "SKIPPED"
        case .skippedICloud:
            return "PENDING"
        case .imported:
            return "IMPORTED"
        case .error:
            return "ERROR"
        }
    }

    var detail: String? {
        switch self {
        case .loading:
            return "Preparing preview..."
        case .ready(let reasonLabel):
            return reasonLabel
        case .duplicate(let existingPath, let strategy, let isReplaceConfirmed):
            if strategy == .replace, isReplaceConfirmed {
                return "Replace confirmed: \(existingPath)"
            }
            return "\(strategy.title): \(existingPath)"
        case .nameConflict(let existingPath, let resolution):
            return "\(resolution.title): \(existingPath)"
        case .iCloudPlaceholder(let path):
            return "iCloud placeholder 需要下载后才能导入：\(path)"
        case .blocked(let message):
            return message
        case .importing(let mode):
            return mode.importingMessage
        case .skippedDuplicate(let existingPath):
            return "Duplicate skipped: \(existingPath)"
        case .skippedICloud(let path):
            return "iCloud pending: \(path)"
        case .imported(let mode):
            return mode.folderImportedMessage
        case .error(let message):
            return message
        }
    }

    var importsIncomingFile: Bool {
        switch self {
        case .ready:
            return true
        case .duplicate(_, let strategy, let isReplaceConfirmed):
            return strategy == .keepBoth || (strategy == .replace && isReplaceConfirmed)
        case .nameConflict(_, let resolution):
            return resolution.importsIncomingFile
        case .loading, .iCloudPlaceholder, .blocked, .importing, .skippedDuplicate, .skippedICloud, .imported, .error:
            return false
        }
    }

    var isFailed: Bool {
        if case .error = self { return true }
        if case .blocked = self { return true }
        return false
    }

    var isImporting: Bool {
        if case .importing = self { return true }
        return false
    }

    var canRunFolderConflictPrecheck: Bool {
        if case .ready = self { return true }
        return false
    }
}

struct ImportFolderPreviewRow: Identifiable, Equatable, Sendable {
    var fileURL: URL
    var rootURL: URL
    var originalName: String
    var relativePath: String
    var sizeBytes: Int64?
    var predictedCategory: String?
    var suggestedName: String
    var status: ImportFolderPreviewRowStatus

    var id: String { fileURL.path }

    var duplicateResolution: ImportBatchDuplicateResolutionStrategy? {
        if case .duplicate(_, let strategy, _) = status { return strategy }
        if case .skippedDuplicate = status { return .skip }
        return nil
    }

    var nameConflictResolution: ImportBatchNameConflictResolution? {
        if case .nameConflict(_, let resolution) = status { return resolution }
        return nil
    }

    var resolvedIncomingName: String {
        guard case .nameConflict(_, let resolution) = status else {
            return suggestedName
        }
        switch resolution {
        case .keepBoth, .replace:
            return suggestedName
        case .renameIncoming(let name):
            return name
        }
    }

    var isConflictReviewRow: Bool {
        switch status {
        case .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .skippedDuplicate, .skippedICloud:
            return true
        case .loading, .ready, .importing, .imported, .error:
            return false
        }
    }

    var isBlockedForImport: Bool {
        switch status {
        case .blocked:
            return true
        case .duplicate(_, .replace, false):
            return true
        case .nameConflict(_, .replace(false)):
            return true
        case .nameConflict(_, .renameIncoming(let name)):
            return ImportSingleFileFilenameValidator.validationMessage(for: name) != nil
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .importing,
             .skippedDuplicate, .skippedICloud, .imported, .error:
            return false
        }
    }

    var existingConflictPath: String? {
        switch status {
        case .duplicate(let existingPath, _, _), .nameConflict(let existingPath, _), .skippedDuplicate(let existingPath):
            return existingPath
        case .loading, .ready, .iCloudPlaceholder, .blocked, .importing, .skippedICloud, .imported, .error:
            return nil
        }
    }

    var conflictLabel: String {
        switch status {
        case .duplicate, .skippedDuplicate:
            return "Duplicate content"
        case .nameConflict:
            return "Same name, different content"
        case .iCloudPlaceholder, .skippedICloud:
            return "iCloud placeholder"
        case .blocked:
            return "Blocked"
        case .loading, .ready, .importing, .imported, .error:
            return "-"
        }
    }

    static func loading(fileURL: URL, rootURL: URL) -> ImportFolderPreviewRow {
        ImportFolderPreviewRow(
            fileURL: fileURL,
            rootURL: rootURL,
            originalName: fileURL.lastPathComponent,
            relativePath: relativePath(for: fileURL, rootURL: rootURL),
            sizeBytes: Self.sizeBytes(for: fileURL),
            predictedCategory: nil,
            suggestedName: fileURL.lastPathComponent,
            status: .loading
        )
    }

    func withPrediction(_ prediction: ClassifyResultSnapshot) -> ImportFolderPreviewRow {
        var row = self
        row.predictedCategory = prediction.category
        row.suggestedName = prediction.suggestedName.isEmpty ? originalName : prediction.suggestedName
        row.status = .ready(reasonLabel: "\(prediction.reason.displayLabel) · \(prediction.confidencePercent)%")
        return row
    }

    func withStatus(_ status: ImportFolderPreviewRowStatus) -> ImportFolderPreviewRow {
        var row = self
        row.status = status
        return row
    }

    private static func sizeBytes(for url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    private static func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        let startIndex = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
        let relative = filePath[startIndex...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? fileURL.lastPathComponent : relative
    }
}

private extension ImportSingleFileStorageMode {
    var folderImportedMessage: String {
        switch self {
        case .copy:
            return "已复制导入"
        case .move:
            return "已移动导入"
        case .indexOnly:
            return "已写入索引"
        }
    }
}
