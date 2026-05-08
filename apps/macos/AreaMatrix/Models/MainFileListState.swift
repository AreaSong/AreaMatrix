import Foundation

enum DetailPaneTab: String, CaseIterable, Identifiable, Sendable {
    case meta
    case log
    case note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meta:
            return "Meta"
        case .log:
            return "Log"
        case .note:
            return "Note"
        }
    }
}

enum MainFileSelectionState: Equatable, Sendable {
    case none
    case single(Int64)
    case multiple(Set<Int64>)

    var singleFileID: Int64? {
        if case .single(let id) = self { return id }
        return nil
    }

    var isMultiple: Bool {
        if case .multiple = self { return true }
        return false
    }

    var multipleFileIDs: Set<Int64> {
        if case .multiple(let ids) = self { return ids }
        return []
    }
}

enum MainFileActionDestination: Equatable, Sendable {
    case rename(fileID: Int64)
    case changeCategory(fileID: Int64)
    case delete(fileID: Int64)

    var pageID: String {
        switch self {
        case .rename:
            return "S1-33"
        case .changeCategory:
            return "S1-35"
        case .delete:
            return "S1-34"
        }
    }

    var pageTitle: String {
        switch self {
        case .rename:
            return "Rename File"
        case .changeCategory:
            return "Change Category"
        case .delete:
            return "Move File to Trash?"
        }
    }

    var fileID: Int64 {
        switch self {
        case .rename(let fileID), .changeCategory(let fileID), .delete(let fileID):
            return fileID
        }
    }
}

extension MainFileActionDestination: Identifiable {
    var id: String {
        "\(pageID)-\(fileID)"
    }
}

enum MainListStatusBanner: Equatable, Sendable {
    case renamedPreservedSelection(fileID: Int64)
    case removedSelectedFile(fileID: Int64)
    case unsavedNoteDraftPreserved(fileID: Int64)

    var message: String {
        switch self {
        case .renamedPreservedSelection:
            return "File renamed. The same file remains selected."
        case .removedSelectedFile:
            return "Selected file is missing or was removed outside AreaMatrix."
        case .unsavedNoteDraftPreserved:
            return "无法保存笔记。草稿已保留，返回该文件的 Note tab 后可继续重试。"
        }
    }
}

enum MainDetailTabRequest: Equatable, Sendable {
    case automatic(DetailPaneTab)
}

enum MainFileWriteActionDisabledReason: String, Equatable, Sendable {
    case repoReadOnly = "Repository is read-only"
    case listLoading = "Current list is loading"
    case importLocked = "This file is locked by an import"
}

enum MainFileRenameState: Equatable, Sendable {
    case idle
    case renaming(fileID: Int64)
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isRenaming: Bool {
        if case .renaming = self { return true }
        return false
    }

    func failure(for fileID: Int64) -> CoreErrorMappingSnapshot? {
        guard case .failed(let failedFileID, let mapping) = self,
              failedFileID == fileID else { return nil }
        return mapping
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

enum MainListDiagnosticsState: Equatable, Sendable {
    case idle
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

enum MainDetailLogState: Equatable, Sendable {
    case notLoaded
    case loading(fileID: Int64)
    case loaded(fileID: Int64, entries: [ChangeLogEntrySnapshot])
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum MainDetailLogDiagnosticsState: Equatable, Sendable {
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

struct MultiSelectionDetailSummary: Equatable, Sendable {
    var selectedCount: Int
    var files: [FileEntrySnapshot]
    var unresolvedMetadataCount: Int
    var isUpdating: Bool

    init(selection: MainFileSelectionState, files: [FileEntrySnapshot], isUpdating: Bool = false) {
        let selectedIDs = selection.multipleFileIDs
        selectedCount = selectedIDs.count
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

    var paths: [String] {
        files.map(\.path)
    }

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
            MultiSelectionSummaryRow(label: "Latest imported", value: importedDateDisplay { $0.max() }),
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

    private static func orderedSelectedFiles(
        from files: [FileEntrySnapshot],
        selectedIDs: Set<Int64>
    ) -> [FileEntrySnapshot] {
        files.filter { selectedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                lhs.currentName.localizedStandardCompare(rhs.currentName) == .orderedAscending
            }
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

struct MultiSelectionSummaryRow: Equatable, Identifiable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}
