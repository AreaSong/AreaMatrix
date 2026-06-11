import Foundation

enum SearchFilterChipKind: String, Equatable {
    case category
    case fileKind
    case tags
    case importedDate
    case modifiedDate
    case storage
    case includeDeleted
}

struct SearchFilterChip: Identifiable, Equatable {
    var kind: SearchFilterChipKind
    var label: String

    var id: SearchFilterChipKind {
        kind
    }
}

enum SearchFilterChips {
    static func items(for filters: SearchFilterStateSnapshot) -> [SearchFilterChip] {
        var chips: [SearchFilterChip] = []
        append(filters.category, kind: .category, prefix: "Category", to: &chips)
        append(filters.fileKind, kind: .fileKind, prefix: "Type", to: &chips)
        if !filters.tags.isEmpty {
            chips.append(SearchFilterChip(kind: .tags, label: "tag:\(filters.tags.joined(separator: ","))"))
        }
        appendDate(.modified, filters: filters, kind: .modifiedDate, title: "Modified", to: &chips)
        appendDate(.imported, filters: filters, kind: .importedDate, title: "Imported", to: &chips)
        if let storageMode = filters.storageMode {
            chips.append(SearchFilterChip(kind: .storage, label: "Storage: \(storageMode.displayName)"))
        }
        if filters.includeDeleted {
            chips.append(SearchFilterChip(kind: .includeDeleted, label: "Include deleted"))
        }
        return chips
    }

    private static func append(
        _ value: String?,
        kind: SearchFilterChipKind,
        prefix: String,
        to chips: inout [SearchFilterChip]
    ) {
        guard let value, !value.isEmpty else { return }
        chips.append(SearchFilterChip(kind: kind, label: "\(prefix): \(value)"))
    }

    private static func appendDate(
        _ field: SearchFilterDateField,
        filters: SearchFilterStateSnapshot,
        kind: SearchFilterChipKind,
        title: String,
        to chips: inout [SearchFilterChip]
    ) {
        guard field.afterTimestamp(in: filters) != nil || field.beforeTimestamp(in: filters) != nil else { return }
        chips.append(SearchFilterChip(kind: kind, label: "\(title): \(field.summary(in: filters))"))
    }
}
