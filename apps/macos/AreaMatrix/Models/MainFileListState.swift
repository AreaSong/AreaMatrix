import Foundation

enum DetailPaneTab: String, CaseIterable, Identifiable {
    case meta
    case log
    case note

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .meta:
            "Meta"
        case .log:
            "Log"
        case .note:
            "Note"
        }
    }
}

enum MainFileSelectionState: Equatable {
    case none
    case single(Int64)
    case multiple(Set<Int64>)

    var singleFileID: Int64? {
        if case let .single(id) = self { return id }
        return nil
    }

    var isMultiple: Bool {
        if case .multiple = self { return true }
        return false
    }

    var multipleFileIDs: Set<Int64> {
        if case let .multiple(ids) = self { return ids }
        return []
    }
}

enum MainFileActionDestination: Equatable {
    case rename(fileID: Int64)
    case changeCategory(fileID: Int64, initialTargetCategory: String? = nil)
    case delete(fileID: Int64)
    case iCloudConflict(fileID: Int64)

    var pageID: String {
        switch self {
        case .rename:
            "S1-33"
        case .changeCategory:
            "S1-35"
        case .delete:
            "S1-34"
        case .iCloudConflict:
            "S1-25"
        }
    }

    var pageTitle: String {
        switch self {
        case .rename:
            "Rename File"
        case .changeCategory:
            "Change Category"
        case .delete:
            "Move File to Trash?"
        case .iCloudConflict:
            "Resolve iCloud Conflict"
        }
    }

    var fileID: Int64 {
        switch self {
        case let .rename(fileID), let .changeCategory(fileID, _), let .delete(fileID), let .iCloudConflict(fileID):
            fileID
        }
    }

    var initialChangeCategoryTarget: String? {
        guard case let .changeCategory(_, targetCategory) = self else { return nil }
        return targetCategory
    }

    func isChangeCategory(fileID expectedFileID: Int64) -> Bool {
        guard case let .changeCategory(fileID, _) = self else { return false }
        return fileID == expectedFileID
    }
}

extension MainFileActionDestination: Identifiable {
    var id: String {
        "\(pageID)-\(fileID)"
    }
}

enum MainFileDeleteOperation: String, Equatable {
    case moveToTrash
    case removeFromIndex

    static func recommended(for file: FileEntrySnapshot) -> MainFileDeleteOperation {
        if file.storageMode == "Indexed" ||
            file.origin == "Adopted" ||
            file.origin == "External" ||
            file.availability == .missing {
            return .removeFromIndex
        }
        return .moveToTrash
    }

    var title: String {
        switch self {
        case .moveToTrash:
            "Move File to Trash?"
        case .removeFromIndex:
            "Remove from Index?"
        }
    }

    var message: String {
        switch self {
        case .moveToTrash:
            "AreaMatrix will move this file to the system Trash and keep a change-log record."
        case .removeFromIndex:
            "This removes the AreaMatrix index entry. It does not delete the original file."
        }
    }

    var confirmationText: String {
        switch self {
        case .moveToTrash:
            "我理解该文件会被移到系统废纸篓"
        case .removeFromIndex:
            "我理解该条目会从 AreaMatrix 索引中移除"
        }
    }

    var actionTitle: String {
        switch self {
        case .moveToTrash:
            "Move to Trash"
        case .removeFromIndex:
            "Remove from Index"
        }
    }

    var runningTitle: String {
        switch self {
        case .moveToTrash:
            "Moving to Trash..."
        case .removeFromIndex:
            "Removing..."
        }
    }

    var failureTitle: String {
        switch self {
        case .moveToTrash:
            "Move to Trash failed"
        case .removeFromIndex:
            "Remove from Index failed"
        }
    }

    func successBanner(fileID: Int64) -> MainListStatusBanner {
        switch self {
        case .moveToTrash:
            .movedFileToTrash(fileID: fileID)
        case .removeFromIndex:
            .removedFileFromIndex(fileID: fileID)
        }
    }
}

enum MainFileDeleteState: Equatable {
    case idle
    case deleting(fileID: Int64, operation: MainFileDeleteOperation)
    case failed(fileID: Int64, operation: MainFileDeleteOperation, CoreErrorMappingSnapshot)

    var isDeleting: Bool {
        if case .deleting = self { return true }
        return false
    }

    func isDeleting(fileID: Int64) -> Bool {
        guard case let .deleting(deletingFileID, _) = self else { return false }
        return deletingFileID == fileID
    }

    func failure(for fileID: Int64) -> CoreErrorMappingSnapshot? {
        guard case let .failed(failedFileID, _, mapping) = self,
              failedFileID == fileID else { return nil }
        return mapping
    }

    func primaryActionTitle(fileID: Int64, operation: MainFileDeleteOperation) -> String {
        if isDeleting(fileID: fileID) { return operation.runningTitle }
        if failure(for: fileID) != nil { return "Retry" }
        return operation.actionTitle
    }
}

enum MainListStatusBanner: Equatable {
    case renamedPreservedSelection(fileID: Int64)
    case removedSelectedFile(fileID: Int64)
    case unsavedNoteDraftPreserved(fileID: Int64)
    case movedFileToTrash(fileID: Int64)
    case removedFileFromIndex(fileID: Int64)
    case batchDeleted(count: Int64)
    case changedCategory(fileID: Int64, category: String)
    case changedBatchCategory(count: Int64, category: String)
    case changedCategoryTreeRefreshFailed(fileID: Int64, category: String)
    case resolvedICloudConflict(fileID: Int64, strategy: ICloudConflictResolutionStrategy)

    var message: String {
        switch self {
        case .renamedPreservedSelection:
            "File renamed. The same file remains selected."
        case .removedSelectedFile:
            "Selected file is missing or was removed outside AreaMatrix."
        case .unsavedNoteDraftPreserved:
            "无法保存笔记。草稿已保留，返回该文件的 Note tab 后可继续重试。"
        case .movedFileToTrash:
            "Moved to Trash. Metadata retained for traceability."
        case .removedFileFromIndex:
            "Removed from AreaMatrix index. Original file was not deleted."
        case let .batchDeleted(count):
            "Processed \(count) selected items. List and undo action log are refreshed."
        case let .changedCategory(_, category):
            "Category changed to \(category). Tree, list, detail, and change log are refreshed."
        case let .changedBatchCategory(count, category):
            "Changed \(count) files to \(category). List and undo action log are refreshed."
        case let .changedCategoryTreeRefreshFailed(_, category):
            """
            Category changed to \(category). List, detail, and change log are refreshed. Retry to refresh Tree counts.
            """
        case let .resolvedICloudConflict(_, strategy):
            strategy.successMessage
        }
    }

    var systemImage: String {
        switch self {
        case .renamedPreservedSelection:
            "arrow.triangle.2.circlepath"
        case .removedSelectedFile, .unsavedNoteDraftPreserved, .changedCategoryTreeRefreshFailed:
            "exclamationmark.triangle"
        case .movedFileToTrash, .removedFileFromIndex, .batchDeleted, .changedCategory, .changedBatchCategory,
             .resolvedICloudConflict:
            "checkmark.circle"
        }
    }
}

enum MainDetailTabRequest: Equatable {
    case automatic(DetailPaneTab)
}

enum MainFileWriteActionDisabledReason: String, Equatable {
    case repoReadOnly = "Repository is read-only"
    case listLoading = "Current list is loading"
    case importLocked = "This file is locked by an import"
}

enum MainFileRenameState: Equatable {
    case idle
    case renaming(fileID: Int64)
    case returningToChangeCategory(fileID: Int64, targetCategory: String)
    case renamingFromChangeCategory(fileID: Int64, targetCategory: String)
    case failed(fileID: Int64, CoreErrorMappingSnapshot)
    case failedFromChangeCategory(fileID: Int64, targetCategory: String, CoreErrorMappingSnapshot)

    var isRenaming: Bool {
        switch self {
        case .renaming, .renamingFromChangeCategory:
            true
        case .idle, .returningToChangeCategory, .failed, .failedFromChangeCategory:
            false
        }
    }

    func failure(for fileID: Int64) -> CoreErrorMappingSnapshot? {
        switch self {
        case let .failed(failedFileID, mapping) where failedFileID == fileID:
            mapping
        case let .failedFromChangeCategory(failedFileID, _, mapping) where failedFileID == fileID:
            mapping
        default:
            nil
        }
    }

    func changeCategoryReturnTarget(for fileID: Int64) -> String? {
        switch self {
        case let .returningToChangeCategory(returningFileID, targetCategory) where returningFileID == fileID:
            targetCategory
        case let .renamingFromChangeCategory(returningFileID, targetCategory) where returningFileID == fileID:
            targetCategory
        case let .failedFromChangeCategory(returningFileID, targetCategory, _) where returningFileID == fileID:
            targetCategory
        default:
            nil
        }
    }
}

enum MainFileActionCategoryOptions {
    static func availableCategories(
        file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> [String] {
        let categories = categoryRows.compactMap(\.categoryForFileList)
        let current = file.map { [$0.category] } ?? []
        return Array(Set(categories + current)).sorted()
    }

    static func defaultTargetCategory(
        for file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> String {
        let categories = availableCategories(file: nil, categoryRows: categoryRows)
        return categories.first { $0 != file?.category } ?? file?.category ?? ""
    }
}

enum MainListDiagnosticsState: Equatable {
    case idle
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

enum MainDetailLogState: Equatable {
    case notLoaded
    case loading(fileID: Int64)
    case loaded(fileID: Int64, entries: [ChangeLogEntrySnapshot])
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum MainDetailLogDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy(fileID: Int64)
    case collecting(fileID: Int64)
    case collected(fileID: Int64, DiagnosticsSnapshotSnapshot)
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}

struct MultiSelectionDetailSummary: Equatable {
    var selectedCount: Int
    var files: [FileEntrySnapshot]
    var listOrderedFileIDs: [Int64]
    var unresolvedMetadataCount: Int
    var isUpdating: Bool

    init(selection: MainFileSelectionState, files: [FileEntrySnapshot], isUpdating: Bool = false) {
        let selectedIDs = selection.multipleFileIDs
        selectedCount = selectedIDs.count
        listOrderedFileIDs = files.filter { selectedIDs.contains($0.id) }.map(\.id)
        self.files = Self.orderedSelectedFiles(from: files, selectedIDs: selectedIDs)
        unresolvedMetadataCount = max(0, selectedIDs.count - self.files.count)
        self.isUpdating = isUpdating
    }

    var title: String {
        "\(selectedCount) 个文件已选中"
    }

    var subtitle: String {
        if categories.count == 1, let category = categories.first {
            return "\(category) 中的 \(selectedCount) 个项目"
        }
        if categories.count > 1 {
            return "跨 \(categories.count) 个分类的 \(selectedCount) 个项目"
        }
        return "\(selectedCount) 个项目"
    }

    var paths: [String] { files.map(\.path) }

    var warningMessages: [String] {
        var warnings: [String] = []
        if unresolvedMetadataCount > 0 {
            warnings.append("部分选中项无法读取元数据")
        }
        if missingCount > 0 {
            warnings.append("选中的文件中有 \(missingCount) 个缺失条目")
        }
        if indexOnlyCount > 0 {
            warnings.append("某些条目的来源路径可能在资料库外")
        }
        return warnings
    }

    var statisticRows: [MultiSelectionSummaryRow] {
        [
            MultiSelectionSummaryRow(label: "Total size", value: totalSizeDisplay),
            MultiSelectionSummaryRow(label: "Categories", value: categoriesDisplay),
            MultiSelectionSummaryRow(label: "Storage modes", value: storageModesDisplay),
            MultiSelectionSummaryRow(label: "Earliest imported", value: importedDateDisplay { $0.min() }),
            MultiSelectionSummaryRow(label: "Latest imported", value: importedDateDisplay { $0.max() })
        ]
    }

    var fileTypeRows: [MultiSelectionSummaryRow] {
        let groupedTypes = Dictionary(grouping: files.map(Self.fileTypeLabel), by: { $0 })
        return groupedTypes.map { label, values in
            (label: label, count: values.count)
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.label < rhs.label
        }
        .map { MultiSelectionSummaryRow(label: $0.label, value: "\($0.count)") }
    }

    private var categories: [String] {
        uniqueSorted(files.map(\.category))
    }

    private var categoriesDisplay: String {
        displayList(categories)
    }

    private var storageModesDisplay: String {
        displayList(uniqueSorted(files.map(\.storageMode)))
    }

    private var totalSizeDisplay: String {
        ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file)
    }

    private var missingCount: Int {
        files.filter { $0.availability == .missing }.count
    }

    private var indexOnlyCount: Int {
        files.filter { $0.storageMode == "Indexed" }.count
    }

    private func importedDateDisplay(_ valueSelector: ([Int64]) -> Int64?) -> String {
        let importedValues = files.map(\.importedAt)
        guard let timestamp = valueSelector(importedValues) else { return "Not available" }
        return FileEntrySnapshot.mainDisplayDateFormatter.string(
            from: Date(timeIntervalSince1970: TimeInterval(timestamp))
        )
    }

    private static func orderedSelectedFiles(from files: [FileEntrySnapshot], selectedIDs: Set<Int64>) -> [FileEntrySnapshot] {
        files.filter { selectedIDs.contains($0.id) }
            .sorted { $0.currentName.localizedStandardCompare($1.currentName) == .orderedAscending }
    }

    private static func fileTypeLabel(for file: FileEntrySnapshot) -> String {
        let fileExtension = (file.currentName as NSString).pathExtension.lowercased()
        switch fileExtension {
        case "pdf":
            return "PDF"
        case "md", "markdown":
            return "Markdown"
        case "png", "jpg", "jpeg", "gif", "heic", "webp":
            return "Image"
        case "":
            return "No Extension"
        default:
            return fileExtension.uppercased()
        }
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private func displayList(_ values: [String]) -> String {
        values.isEmpty ? "Not available" : values.joined(separator: ", ")
    }
}

struct MultiSelectionSummaryRow: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String {
        label
    }
}
