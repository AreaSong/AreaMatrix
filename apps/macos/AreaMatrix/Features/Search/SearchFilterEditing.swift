import AreaMatrixFeatureLibrary
import Foundation

struct SearchDateRangeEditResult: Equatable {
    var updatedFilters: SearchFilterStateSnapshot?
    var errorMessage: LocalizedMessage?
}

enum SearchFilterEditing {
    static func optionalFacetValue(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    static func settingSingleTag(_ value: String, in filters: SearchFilterStateSnapshot) -> SearchFilterStateSnapshot {
        var updated = filters
        updated.tags = value.isEmpty ? [] : [value]
        return updated
    }

    static func togglingTag(_ value: String, in filters: SearchFilterStateSnapshot) -> SearchFilterStateSnapshot {
        let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return filters }

        var updated = filters
        if containsTag(tag, in: updated.tags) {
            updated.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        } else {
            updated.tags.append(tag)
        }
        if updated.tags.isEmpty {
            updated.tagMatchMode = .any
        }
        return updated
    }

    static func settingTagMatchMode(
        _ mode: SearchTagMatchModeSnapshot,
        in filters: SearchFilterStateSnapshot
    ) -> SearchFilterStateSnapshot {
        var updated = filters
        updated.tagMatchMode = mode
        return updated
    }

    static func removingTag(_ value: String, from filters: SearchFilterStateSnapshot) -> SearchFilterStateSnapshot {
        let tag = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return filters }

        var updated = filters
        updated.tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        if updated.tags.isEmpty {
            updated.tagMatchMode = .any
        }
        return updated
    }

    static func settingDatePreset(
        _ preset: SearchDateFilterPreset,
        field: SearchFilterDateField,
        in filters: SearchFilterStateSnapshot,
        now: Date = Date()
    ) -> SearchFilterStateSnapshot {
        field.applying(after: lowerBound(for: preset, now: now), to: filters)
    }

    static func settingCustomDateRange(
        from: Date,
        until: Date,
        field: SearchFilterDateField,
        in filters: SearchFilterStateSnapshot
    ) -> SearchDateRangeEditResult {
        let start = Int64(Calendar.current.startOfDay(for: from).timeIntervalSince1970)
        let end = Int64(Calendar.current.startOfDay(for: until).timeIntervalSince1970)
        guard start <= end else {
            return SearchDateRangeEditResult(
                updatedFilters: nil,
                errorMessage: L10n.message("End date must be after start date.")
            )
        }
        return SearchDateRangeEditResult(
            updatedFilters: field.applying(after: start, before: end, to: filters),
            errorMessage: nil
        )
    }

    static func settingStorage(_ rawValue: String, in filters: SearchFilterStateSnapshot) -> SearchFilterStateSnapshot {
        var updated = filters
        updated.storageMode = SearchStorageModeSnapshot(rawValue: rawValue)
        return updated
    }

    static func settingIncludeDeleted(
        _ value: Bool,
        in filters: SearchFilterStateSnapshot
    ) -> SearchFilterStateSnapshot {
        var updated = filters
        updated.includeDeleted = value
        return updated
    }

    static func removing(
        _ chipKind: SearchFilterChipKind,
        from filters: SearchFilterStateSnapshot
    ) -> SearchFilterStateSnapshot {
        var updated = filters
        switch chipKind {
        case .category:
            updated.category = nil
        case .fileKind:
            updated.fileKind = nil
        case .tags:
            updated.tags = []
            updated.tagMatchMode = .any
        case .importedDate:
            updated = SearchFilterDateField.imported.clearing(in: updated)
        case .modifiedDate:
            updated = SearchFilterDateField.modified.clearing(in: updated)
        case .storage:
            updated.storageMode = nil
        case .includeDeleted:
            updated.includeDeleted = false
        }
        return updated
    }

    private static func lowerBound(for preset: SearchDateFilterPreset, now: Date) -> Int64? {
        switch preset {
        case .any:
            nil
        case .last7Days:
            Int64(now.addingTimeInterval(-7 * 24 * 60 * 60).timeIntervalSince1970)
        case .last30Days:
            Int64(now.addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970)
        case .thisYear:
            Calendar.current.date(from: Calendar.current.dateComponents([.year], from: now))
                .map { Int64($0.timeIntervalSince1970) }
        }
    }

    private static func containsTag(_ tag: String, in tags: [String]) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }
}
