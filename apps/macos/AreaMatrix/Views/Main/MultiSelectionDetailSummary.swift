import Foundation

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

    var paths: [String] {
        files.map(\.path)
    }

    var warningMessages: [String] {
        var warnings: [String] = []
        if unresolvedMetadataCount > 0 { warnings.append("部分选中项无法读取元数据") }
        if missingCount > 0 { warnings.append("选中的文件中有 \(missingCount) 个缺失条目") }
        if indexOnlyCount > 0 { warnings.append("某些条目的来源路径可能在资料库外") }
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

    private static func orderedSelectedFiles(
        from files: [FileEntrySnapshot],
        selectedIDs: Set<Int64>
    ) -> [FileEntrySnapshot] {
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
