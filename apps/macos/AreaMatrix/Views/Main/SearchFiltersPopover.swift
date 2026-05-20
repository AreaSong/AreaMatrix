import SwiftUI

struct SearchDateRangeEditResult: Equatable {
    var updatedFilters: SearchFilterStateSnapshot?
    var errorMessage: String?
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
        to: Date,
        field: SearchFilterDateField,
        in filters: SearchFilterStateSnapshot
    ) -> SearchDateRangeEditResult {
        let start = Int64(Calendar.current.startOfDay(for: from).timeIntervalSince1970)
        let end = Int64(Calendar.current.startOfDay(for: to).timeIntervalSince1970)
        guard start <= end else {
            return SearchDateRangeEditResult(
                updatedFilters: nil,
                errorMessage: "End date must be after start date."
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

struct SearchFiltersPopover: View {
    @Binding var filters: SearchFilterStateSnapshot
    var facetsState: MainSearchFacetsState
    var canSaveAsSmartList: Bool
    var saveDisabledReason: String?
    var onReset: () -> Void
    var onRetry: () -> Void
    var onSaveAsSmartList: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            facetStatus
            Divider()
            filterControls
            SearchFilterChipsBar(filters: $filters)
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
        } else if facetsState.isLoading {
            Label("Loading filter counts...", systemImage: "clock.arrow.circlepath")
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
                options: facetsState.facets?.categories ?? [],
                isLoading: facetsState.isLoading,
                emptyMessage: "No categories yet"
            )
            SearchFacetPicker(
                title: "Type",
                allLabel: "All types",
                selection: $filters.fileKind,
                options: facetsState.facets?.fileKinds ?? [],
                isLoading: facetsState.isLoading,
                emptyMessage: "No file types yet"
            )
            SearchTagFacetPicker(
                filters: $filters,
                facetsState: facetsState,
                onRetry: onRetry
            )
            SearchDateFilterSection(
                title: "Modified",
                field: .modified,
                bounds: facetsState.facets?.dateBounds,
                filters: $filters
            )
            SearchDateFilterSection(
                title: "Imported",
                field: .imported,
                bounds: facetsState.facets?.dateBounds,
                filters: $filters
            )
            SearchStorageFacetPicker(filters: $filters, options: facetsState.facets?.storageModes ?? [])
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
            if let saveDisabledReason, !canSaveAsSmartList {
                Text(saveDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Retry", action: onRetry)
                .disabled(facetsState.errorMapping == nil)
            Button("Save as Smart List", action: onSaveAsSmartList)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSaveAsSmartList)
            Button("Close") { dismiss() }
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
    var isLoading: Bool
    var emptyMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            if options.isEmpty {
                Text(isLoading ? "Loading..." : emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SearchDateFilterSection: View {
    var title: String
    var field: SearchFilterDateField
    var bounds: SearchDateFacetBoundsSnapshot?
    @Binding var filters: SearchFilterStateSnapshot
    @State private var validationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Menu(dateSummary) {
                    Button("Any") { applyPreset(.any) }
                    Button("Last 7 days") { applyPreset(.last7Days) }
                    Button("Last 30 days") { applyPreset(.last30Days) }
                    Button("This year") { applyPreset(.thisYear) }
                    Button("Custom...") {
                        applyCustomRange(from: customFromDate, to: customToDate)
                    }
                }
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) date filter, \(dateSummary)")
            if field.hasCustomRange(in: filters) {
                customDatePickers
            }
            if let validationError {
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("\(title) date error, \(validationError)")
            }
        }
    }

    private var dateSummary: String {
        field.summary(in: filters)
    }

    private var customDatePickers: some View {
        VStack(alignment: .leading, spacing: 4) {
            DatePicker("From", selection: fromBinding, in: allowedDateRange, displayedComponents: [.date])
            DatePicker("To", selection: toBinding, in: allowedDateRange, displayedComponents: [.date])
        }
    }

    private var fromBinding: Binding<Date> {
        Binding(
            get: { customFromDate },
            set: { applyCustomRange(from: $0, to: customToDate) }
        )
    }

    private var toBinding: Binding<Date> {
        Binding(
            get: { customToDate },
            set: { applyCustomRange(from: customFromDate, to: $0) }
        )
    }

    private var customFromDate: Date {
        field.afterTimestamp(in: filters).map { Date(timeIntervalSince1970: TimeInterval($0)) } ??
            Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    private var customToDate: Date {
        field.beforeTimestamp(in: filters).map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
    }

    private var allowedDateRange: ClosedRange<Date> {
        field.allowedDateRange(from: bounds)
    }

    private func applyPreset(_ preset: SearchDateFilterPreset) {
        validationError = nil
        filters = SearchFilterEditing.settingDatePreset(preset, field: field, in: filters)
    }

    private func applyCustomRange(from: Date, to: Date) {
        let result = SearchFilterEditing.settingCustomDateRange(from: from, to: to, field: field, in: filters)
        if let updated = result.updatedFilters {
            validationError = nil
            filters = updated
            return
        }
        validationError = result.errorMessage
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

struct SearchFilterChipsBar: View {
    @Binding var filters: SearchFilterStateSnapshot

    var body: some View {
        let chips = SearchFilterChips.items(for: filters)
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button {
                            filters = SearchFilterEditing.removing(chip.kind, from: filters)
                        } label: {
                            Label(chip.label, systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Remove filter \(chip.label)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(chips.count) active filters")
        }
    }
}

extension MainSearchFacetsState {
    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension SearchFacetCountSnapshot {
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
