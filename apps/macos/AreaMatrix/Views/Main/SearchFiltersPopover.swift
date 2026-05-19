import SwiftUI

struct SearchFiltersPopover: View {
    @Binding var filters: SearchFilterStateSnapshot
    var facetsState: MainSearchFacetsState
    var onReset: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            facetStatus
            Divider()
            filterControls
            footer
        }
        .padding(16)
        .frame(width: 360, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Filters")
                .font(.headline)
            Text(activeSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var facetStatus: some View {
        if let error = facetsState.errorMapping {
            Label("Could not load filters: \(error.userMessage)", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let facets = facetsState.facets {
            Label("\(facets.totalCount) matching files", systemImage: "number")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Label("Filter counts load after entering a query", systemImage: "line.3.horizontal.decrease.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchFacetPicker(
                title: "Category",
                allLabel: "All categories",
                selection: $filters.category,
                options: facetsState.facets?.categories ?? []
            )
            SearchFacetPicker(
                title: "Type",
                allLabel: "All types",
                selection: $filters.fileKind,
                options: facetsState.facets?.fileKinds ?? []
            )
            SearchTagFacetPicker(
                filters: $filters,
                options: facetsState.facets?.tags ?? []
            )
            SearchDateFilterMenu(title: "Modified", field: .modified, filters: $filters)
            SearchDateFilterMenu(title: "Imported", field: .imported, filters: $filters)
            SearchStorageFacetPicker(
                filters: $filters,
                options: facetsState.facets?.storageModes ?? []
            )
            Toggle(
                "Include deleted files",
                isOn: Binding(
                    get: { filters.includeDeleted },
                    set: { filters = SearchFilterEditing.settingIncludeDeleted($0, in: filters) }
                )
            )
                .accessibilityLabel("Include deleted files")
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset filters", action: onReset)
                .disabled(filters.isEmpty)
            Spacer()
            Button("Retry", action: onRetry)
                .disabled(facetsState.errorMapping == nil)
        }
    }

    private var activeSummary: String {
        let count = facetsState.facets?.activeFilterCount ?? filters.activeFilterCount
        return "\(count) filters active"
    }
}

private struct SearchFacetPicker: View {
    var title: String
    var allLabel: String
    @Binding var selection: String?
    var options: [SearchFacetCountSnapshot]

    var body: some View {
        Picker(title, selection: Binding(
            get: { selection ?? "" },
            set: { selection = SearchFilterEditing.optionalFacetValue($0) }
        )) {
            Text(allLabel).tag("")
            ForEach(options) { option in
                Text(option.displayTitle).tag(option.value)
            }
        }
        .disabled(options.isEmpty)
        .accessibilityLabel("\(title) filter")
    }
}

private struct SearchTagFacetPicker: View {
    @Binding var filters: SearchFilterStateSnapshot
    var options: [SearchFacetCountSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Tags", selection: Binding(
                get: { filters.tags.first ?? "" },
                set: { filters = SearchFilterEditing.settingSingleTag($0, in: filters) }
            )) {
                Text("Any tag").tag("")
                ForEach(options) { option in
                    Text(option.displayTitle).tag(option.value)
                }
            }
            .disabled(options.isEmpty)
            .accessibilityLabel("Tags filter")
            Picker("Tag match", selection: Binding(
                get: { filters.tagMatchMode },
                set: { filters = SearchFilterEditing.settingTagMatchMode($0, in: filters) }
            )) {
                Text("Any selected tag").tag(SearchTagMatchModeSnapshot.any)
                Text("All selected tags").tag(SearchTagMatchModeSnapshot.all)
            }
            .disabled(filters.tags.count < 2)
        }
    }
}

private struct SearchDateFilterMenu: View {
    var title: String
    var field: SearchFilterDateField
    @Binding var filters: SearchFilterStateSnapshot

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Menu(dateSummary) {
                Button("Any") {
                    filters = SearchFilterEditing.settingDatePreset(.any, field: field, in: filters)
                }
                Button("Last 7 days") {
                    filters = SearchFilterEditing.settingDatePreset(.last7Days, field: field, in: filters)
                }
                Button("Last 30 days") {
                    filters = SearchFilterEditing.settingDatePreset(.last30Days, field: field, in: filters)
                }
                Button("This year") {
                    filters = SearchFilterEditing.settingDatePreset(.thisYear, field: field, in: filters)
                }
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) date filter, \(dateSummary)")
    }

    private var dateSummary: String {
        field.summary(in: filters)
    }
}

private struct SearchStorageFacetPicker: View {
    @Binding var filters: SearchFilterStateSnapshot
    var options: [SearchStorageModeFacetCountSnapshot]

    var body: some View {
        Picker("Storage", selection: Binding(
            get: { filters.storageMode?.rawValue ?? "" },
            set: { filters = SearchFilterEditing.settingStorage($0, in: filters) }
        )) {
            Text("All storage modes").tag("")
            ForEach(storageOptions) { option in
                Text(option.displayTitle).tag(option.value.rawValue)
            }
        }
        .accessibilityLabel("Storage filter")
    }

    private var storageOptions: [SearchStorageModeFacetCountSnapshot] {
        options.isEmpty ? SearchStorageModeFacetCountSnapshot.defaultOptions : options
    }
}

enum SearchDateFilterPreset {
    case any
    case last7Days
    case last30Days
    case thisYear
}

enum SearchFilterDateField {
    case imported
    case modified

    func summary(in filters: SearchFilterStateSnapshot) -> String {
        let timestamp = afterTimestamp(in: filters)
        return timestamp.map { "Since \(Self.formatter.string(from: Date(timeIntervalSince1970: TimeInterval($0))))" } ?? "Any"
    }

    fileprivate func applying(after: Int64?, to filters: SearchFilterStateSnapshot) -> SearchFilterStateSnapshot {
        var updated = filters
        switch self {
        case .imported:
            updated.importedAfter = after
            updated.importedBefore = nil
        case .modified:
            updated.modifiedAfter = after
            updated.modifiedBefore = nil
        }
        return updated
    }

    private func afterTimestamp(in filters: SearchFilterStateSnapshot) -> Int64? {
        switch self {
        case .imported:
            filters.importedAfter
        case .modified:
            filters.modifiedAfter
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

enum SearchFilterEditing {
    static func optionalFacetValue(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    static func settingSingleTag(
        _ value: String,
        in filters: SearchFilterStateSnapshot
    ) -> SearchFilterStateSnapshot {
        var updated = filters
        updated.tags = value.isEmpty ? [] : [value]
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

    static func settingDatePreset(
        _ preset: SearchDateFilterPreset,
        field: SearchFilterDateField,
        in filters: SearchFilterStateSnapshot,
        now: Date = Date()
    ) -> SearchFilterStateSnapshot {
        field.applying(after: lowerBound(for: preset, now: now), to: filters)
    }

    static func settingStorage(
        _ rawValue: String,
        in filters: SearchFilterStateSnapshot
    ) -> SearchFilterStateSnapshot {
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
}

private extension SearchFacetCountSnapshot {
    var displayTitle: String {
        disabled ? "\(label) (0)" : "\(label) (\(count))"
    }
}

private extension SearchStorageModeFacetCountSnapshot {
    static var defaultOptions: [SearchStorageModeFacetCountSnapshot] {
        SearchStorageModeSnapshot.allCases.map {
            SearchStorageModeFacetCountSnapshot(
                value: $0,
                label: $0.displayName,
                count: 0,
                selected: false,
                disabled: false
            )
        }
    }

    var displayTitle: String {
        disabled ? "\(label) (0)" : "\(label) (\(count))"
    }
}
