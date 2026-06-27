import Foundation

@MainActor
extension ImportBatchCopyImportModel {
    var currentImportPath: String? {
        switch status {
        case let .importing(_, _, _, currentPath):
            currentPath
        case .idle, .imported:
            importableRows.first.map { targetRelativePath(for: $0, destination: selectedDestination) }
        }
    }

    var importDisabledReason: String? {
        if status.isImporting {
            return selectedStorageMode.importingBlockingMessage
        }
        if isICloudDownloading {
            return "正在下载 iCloud 文件"
        }
        if blockedCount > 0 {
            return "存在 BLOCKED 项，请先完成冲突处理"
        }
        if isAllRowsUnavailable {
            return "没有可导入的批量项目"
        }
        if !hasActionableRows {
            return "没有可导入或可跳过的批量项目"
        }
        return nil
    }

    var importableRows: [ImportBatchCopyImportRow] {
        rows.filter { row in
            if row.status.isReady { return true }
            return row.duplicateResolution?.importsIncomingFile == true
                || row.nameConflictResolution?.importsIncomingFile == true
        }
    }

    var skippedDuplicateCount: Int {
        rows.filter { row in
            if case .skippedDuplicate = row.status { return true }
            if row.duplicateResolution == .skip { return true }
            return false
        }.count
    }

    var duplicateCount: Int {
        rows.filter { row in
            if case .duplicate = row.status { return true }
            if case .skippedDuplicate = row.status { return true }
            return false
        }.count
    }

    var nameConflictCount: Int {
        rows.filter { row in
            if case .nameConflict = row.status { return true }
            return false
        }.count
    }

    var iCloudPlaceholderCount: Int {
        rows.filter { row in
            if case .iCloudPlaceholder = row.status { return true }
            return false
        }.count
    }

    var pendingICloudSummaryCount: Int {
        pendingICloudCount
    }

    var previewErrorCount: Int {
        rows.filter { row in
            if case .error = row.status { return true }
            return false
        }.count
    }

    var blockedCount: Int {
        rows.filter(\.isBlockedForImport).count
    }

    var replaceOptionVisibility: ImportSingleFileReplaceOptionVisibility {
        guard request?.allowReplaceDuringImport == true else { return .hidden }
        return request?.isTrashAvailable == true ? .enabled : .disabled
    }

    var hasPendingDuplicateResolution: Bool {
        unresolvedDuplicateCount > 0
    }

    var unresolvedDuplicateCount: Int {
        rows.filter { row in
            if case .duplicate = row.status { return true }
            return false
        }.count
    }

    private var hasActionableRows: Bool {
        !importableRows.isEmpty
            || rows.contains { $0.duplicateResolution == .skip }
            || rows.contains { if case .iCloudPlaceholder = $0.status { return true }; return false }
    }

    private var isAllRowsUnavailable: Bool {
        !rows.isEmpty && importableRows.isEmpty && rows.allSatisfy { row in
            switch row.status {
            case .error, .blocked, .iCloudPlaceholder, .skippedICloud:
                true
            case .loading, .ready, .duplicate, .nameConflict, .importing, .skippedDuplicate, .imported:
                false
            }
        }
    }
}
