import Foundation

protocol ImportFolderScanning: Sendable {
    func scanFolder(rootURL: URL, includeHiddenFiles: Bool, followSymlinks: Bool) async -> ImportFolderScanResult
}

struct ImportFolderScanResult: Equatable {
    var rows: [ImportFolderPreviewRow]
    var folderCount: Int
    var skippedRules: [ImportFolderSkippedRule]
    var errors: [ImportFolderScanError]
}

enum ImportFolderPreviewStatus: Equatable {
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
        case let .scanning(path):
            return "正在预扫描 \(path)"
        case .checkingConflicts:
            return "Checking conflicts..."
        case let .loaded(ready, total, failed):
            if failed == 0 {
                return "已完成 \(total) 个文件的分类预览"
            }
            return "已完成 \(ready)/\(total) 个文件的分类预览，\(failed) 个失败"
        case .empty:
            return "没有可导入文件"
        case let .failed(message):
            return message
        }
    }
}

enum ImportFolderPreviewRowStatus: Equatable {
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
            "PREVIEW"
        case .ready:
            "OK"
        case .duplicate:
            "DUP"
        case .nameConflict:
            "NAME"
        case .iCloudPlaceholder:
            "ICLOUD"
        case .blocked:
            "BLOCKED"
        case .importing:
            "IMPORTING"
        case .skippedDuplicate:
            "SKIPPED"
        case .skippedICloud:
            "PENDING"
        case .imported:
            "IMPORTED"
        case .error:
            "ERROR"
        }
    }

    var detail: String? {
        switch self {
        case .loading:
            return "Preparing preview..."
        case let .ready(reasonLabel):
            return reasonLabel
        case let .duplicate(existingPath, strategy, isReplaceConfirmed):
            if strategy == .replace, isReplaceConfirmed {
                return "Replace confirmed: \(existingPath)"
            }
            return "\(strategy.title): \(existingPath)"
        case let .nameConflict(existingPath, resolution):
            return "\(resolution.title): \(existingPath)"
        case let .iCloudPlaceholder(path):
            return "iCloud placeholder 需要下载后才能导入：\(path)"
        case let .blocked(message):
            return message
        case let .importing(mode):
            return mode.importingMessage
        case let .skippedDuplicate(existingPath):
            return "Duplicate skipped: \(existingPath)"
        case let .skippedICloud(path):
            return "iCloud pending: \(path)"
        case let .imported(mode):
            return mode.folderImportedMessage
        case let .error(message):
            return message
        }
    }

    var importsIncomingFile: Bool {
        switch self {
        case .ready:
            true
        case let .duplicate(_, strategy, isReplaceConfirmed):
            strategy == .keepBoth || (strategy == .replace && isReplaceConfirmed)
        case let .nameConflict(_, resolution):
            resolution.importsIncomingFile
        case .loading, .iCloudPlaceholder, .blocked, .importing, .skippedDuplicate, .skippedICloud, .imported, .error:
            false
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

struct ImportFolderPreviewRow: Identifiable, Equatable {
    var fileURL: URL
    var rootURL: URL
    var originalName: String
    var relativePath: String
    var sizeBytes: Int64?
    var predictedCategory: String?
    var suggestedName: String
    var status: ImportFolderPreviewRowStatus

    var id: String {
        fileURL.path
    }

    var duplicateResolution: ImportBatchDuplicateResolutionStrategy? {
        if case let .duplicate(_, strategy, _) = status { return strategy }
        if case .skippedDuplicate = status { return .skip }
        return nil
    }

    var nameConflictResolution: ImportBatchNameConflictResolution? {
        if case let .nameConflict(_, resolution) = status { return resolution }
        return nil
    }

    var resolvedIncomingName: String {
        guard case let .nameConflict(_, resolution) = status else {
            return suggestedName
        }
        switch resolution {
        case .keepBoth, .replace:
            return suggestedName
        case let .renameIncoming(name):
            return name
        }
    }

    var isConflictReviewRow: Bool {
        switch status {
        case .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .skippedDuplicate, .skippedICloud:
            true
        case .loading, .ready, .importing, .imported, .error:
            false
        }
    }

    var isBlockedForImport: Bool {
        switch status {
        case .blocked:
            true
        case .duplicate(_, .replace, false):
            true
        case .nameConflict(_, .replace(false)):
            true
        case let .nameConflict(_, .renameIncoming(name)):
            ImportSingleFileFilenameValidator.validationMessage(for: name) != nil
        case .loading, .ready, .duplicate, .nameConflict, .iCloudPlaceholder, .importing,
             .skippedDuplicate, .skippedICloud, .imported, .error:
            false
        }
    }

    var existingConflictPath: String? {
        switch status {
        case let .duplicate(existingPath, _, _), let .nameConflict(existingPath, _),
             let .skippedDuplicate(existingPath):
            existingPath
        case .loading, .ready, .iCloudPlaceholder, .blocked, .importing, .skippedICloud, .imported, .error:
            nil
        }
    }

    var conflictLabel: String {
        switch status {
        case .duplicate, .skippedDuplicate:
            "Duplicate content"
        case .nameConflict:
            "Same name, different content"
        case .iCloudPlaceholder, .skippedICloud:
            "iCloud placeholder"
        case .blocked:
            "Blocked"
        case .loading, .ready, .importing, .imported, .error:
            "-"
        }
    }

    static func loading(fileURL: URL, rootURL: URL) -> ImportFolderPreviewRow {
        ImportFolderPreviewRow(
            fileURL: fileURL,
            rootURL: rootURL,
            originalName: fileURL.lastPathComponent,
            relativePath: relativePath(for: fileURL, rootURL: rootURL),
            sizeBytes: sizeBytes(for: fileURL),
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
            "已复制导入"
        case .move:
            "已移动导入"
        case .indexOnly:
            "已写入索引"
        }
    }
}
