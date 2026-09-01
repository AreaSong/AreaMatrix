import AreaMatrixFeatureLibrary
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
        L10n.plural("detail.multiSelection.selectedFiles", count: selectedCount)
    }

    var subtitle: String {
        if categories.count == 1, let category = categories.first {
            return L10n.format("detail.multiSelection.singleCategory", category, selectedCount)
        }
        if categories.count > 1 {
            return L10n.format("detail.multiSelection.multipleCategories", categories.count, selectedCount)
        }
        return L10n.plural("detail.multiSelection.itemCount", count: selectedCount)
    }

    var paths: [String] {
        files.map(\.path)
    }

    var warningMessages: [String] {
        var warnings: [String] = []
        if unresolvedMetadataCount > 0 {
            warnings.append(L10n.string("detail.multiSelection.metadataUnavailable"))
        }
        if missingCount > 0 {
            warnings.append(L10n.plural("detail.multiSelection.missingEntryWarning", count: missingCount))
        }
        if indexOnlyCount > 0 {
            warnings.append(L10n.string("detail.multiSelection.externalSourceWarning"))
        }
        return warnings
    }

    var statisticRows: [MultiSelectionSummaryRow] {
        [
            MultiSelectionSummaryRow(label: L10n.string("Total size"), value: totalSizeDisplay),
            MultiSelectionSummaryRow(label: L10n.string("Categories"), value: categoriesDisplay),
            MultiSelectionSummaryRow(label: L10n.string("Storage modes"), value: storageModesDisplay),
            MultiSelectionSummaryRow(label: L10n.string("Earliest imported"), value: importedDateDisplay { $0.min() }),
            MultiSelectionSummaryRow(label: L10n.string("Latest imported"), value: importedDateDisplay { $0.max() })
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
        guard let timestamp = valueSelector(importedValues) else { return L10n.string("Not available") }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .omitted)
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
            return L10n.string("PDF")
        case "md", "markdown":
            return L10n.string("Markdown")
        case "png", "jpg", "jpeg", "gif", "heic", "webp":
            return L10n.string("Image")
        case "":
            return L10n.string("No Extension")
        default:
            return fileExtension.uppercased()
        }
    }

    private func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private func displayList(_ values: [String]) -> String {
        values.isEmpty ? L10n.string("Not available") : values.joined(separator: ", ")
    }
}

struct MultiSelectionSummaryRow: Equatable, Identifiable {
    let label: String
    let value: String

    var id: String {
        label
    }
}
