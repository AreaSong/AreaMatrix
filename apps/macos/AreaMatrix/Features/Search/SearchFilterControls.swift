import AreaMatrixFeatureLibrary
import SwiftUI

struct SearchFacetPicker: View {
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
            .accessibilityLabel(L10n.format("search.filter.accessibilityLabel", title))
            if options.isEmpty {
                Text(isLoading ? "Loading..." : emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SearchDateFilterSection: View {
    @EnvironmentObject private var localizer: AppLocalizer
    var title: String
    var field: SearchFilterDateField
    var bounds: SearchDateFacetBoundsSnapshot?
    @Binding var filters: SearchFilterStateSnapshot
    @State private var validationError: LocalizedMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Menu(dateSummary) {
                    Button(L10n.string("Any")) { applyPreset(.any) }
                    Button(L10n.string("Last 7 days")) { applyPreset(.last7Days) }
                    Button(L10n.string("Last 30 days")) { applyPreset(.last30Days) }
                    Button(L10n.string("This year")) { applyPreset(.thisYear) }
                    Button(L10n.string("Custom...")) {
                        applyCustomRange(from: customFromDate, until: customToDate)
                    }
                }
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.format("search.dateFilter.accessibilityLabel", title, dateSummary))
            if field.hasCustomRange(in: filters) {
                customDatePickers
            }
            if let validationError {
                let resolvedError = localizer.resolve(validationError)
                Text(resolvedError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel(L10n.format(
                        "search.dateFilter.error.accessibilityLabel",
                        title,
                        resolvedError
                    ))
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
            set: { applyCustomRange(from: $0, until: customToDate) }
        )
    }

    private var toBinding: Binding<Date> {
        Binding(
            get: { customToDate },
            set: { applyCustomRange(from: customFromDate, until: $0) }
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

    private func applyCustomRange(from: Date, until: Date) {
        let result = SearchFilterEditing.settingCustomDateRange(from: from, until: until, field: field, in: filters)
        if let updated = result.updatedFilters {
            validationError = nil
            filters = updated
            return
        }
        validationError = result.errorMessage
    }
}

struct SearchStorageFacetPicker: View {
    @Binding var filters: SearchFilterStateSnapshot
    var options: [SearchStorageModeFacetCountSnapshot]

    var body: some View {
        Picker(L10n.string("Storage"), selection: Binding(
            get: { filters.storageMode?.rawValue ?? "" },
            set: { filters = SearchFilterEditing.settingStorage($0, in: filters) }
        )) {
            Text(L10n.string("All storage modes")).tag("")
            ForEach(storageOptions) { option in
                Text(option.displayTitle).tag(option.value.rawValue)
            }
        }
        .accessibilityLabel(L10n.string("Storage filter"))
    }

    private var storageOptions: [SearchStorageModeFacetCountSnapshot] {
        options.isEmpty ? SearchStorageModeFacetCountSnapshot.defaultOptions : options
    }
}

struct SearchTagFacetPicker: View {
    @Binding var filters: SearchFilterStateSnapshot
    var facetsState: MainSearchFacetsState
    var tagRegistryState: TagFilterRegistryState
    var tagRegistryAnchorFileID: Int64?
    var onRetry: () -> Void
    var onLoadTagRegistry: (Int64?) -> Void
    var onRetryTagRegistry: () -> Void
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("Filter by tags"))
                .font(.callout.weight(.semibold))
            TextField(L10n.string("Search tags"), text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityIdentifier("tag-filters-tag-search")
            SelectedTagChips(filters: $filters, tagFacets: tagOptions)
            TagMatchModeControl(filters: $filters)
            tagList
            tagFooter
        }
        .accessibilityIdentifier("tag-filters-tags-filter")
        .onAppear { isSearchFocused = true }
        .task(id: tagRegistryAnchorFileID) {
            onLoadTagRegistry(tagRegistryAnchorFileID)
        }
    }

    @ViewBuilder
    private var tagList: some View {
        if let error = tagRegistryState.errorMapping, tagOptions.isEmpty {
            tagLoadingFailure(error: error, retry: onRetryTagRegistry)
        } else if let error = facetsState.errorMapping, tagOptions.isEmpty {
            tagLoadingFailure(error: error, retry: onRetry)
        } else if isLoadingTags, tagOptions.isEmpty {
            Text(L10n.string("Loading tags..."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if tagOptions.isEmpty {
            tagEmptyState
        } else if visibleTagOptions.isEmpty {
            Text(L10n.string("No matching tags"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            tagOptionsView
        }
    }

    private var tagOptionsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(visibleTagOptions) { option in
                Toggle(isOn: Binding(
                    get: { option.isSelected(in: filters) },
                    set: { _ in filters = SearchFilterEditing.togglingTag(option.value, in: filters) }
                )) {
                    TagFacetRow(option: option)
                }
                .disabled(option.disabled || tagRegistryState.errorMapping != nil)
                .accessibilityLabel(option.accessibilityLabel(isSelected: option.isSelected(in: filters)))
            }
        }
    }

    private var tagFooter: some View {
        HStack {
            Button(L10n.string("Clear all")) {
                filters = SearchFilterEditing.removing(.tags, from: filters)
            }
            .disabled(filters.tags.isEmpty)
            Spacer()
            tagFooterStatus
        }
    }

    @ViewBuilder
    private var tagFooterStatus: some View {
        if tagRegistryState.errorMapping != nil, !tagOptions.isEmpty {
            Button(L10n.string("Retry tags"), action: onRetryTagRegistry)
                .font(.caption)
        } else if facetsState.errorMapping != nil, !tagOptions.isEmpty {
            Button(L10n.string("Retry counts"), action: onRetry)
                .font(.caption)
        } else if isLoadingTags, !tagOptions.isEmpty {
            Text(L10n.string("Loading tags..."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tagLoadingFailure(error: CoreErrorMappingSnapshot, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(L10n.string("Could not load tags"))
            Button(L10n.string("Retry"), action: retry)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(L10n.format("search.tags.loadError.accessibilityLabel", error.userMessage))
    }

    private var tagEmptyState: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.string("No tags yet"))
            Text(L10n.string("Add tags from file detail or batch actions."))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var tagOptions: [SearchFacetCountSnapshot] {
        TagFilterRegistryPresentation.options(registryState: tagRegistryState, facetsState: facetsState)
    }

    private var visibleTagOptions: [SearchFacetCountSnapshot] {
        TagFacetFiltering.visibleTags(query: query, facets: tagOptions)
    }

    private var isLoadingTags: Bool {
        tagRegistryState.isLoading || facetsState.isLoading
    }
}

private struct TagFacetRow: View {
    var option: SearchFacetCountSnapshot

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(option.disabled ? 0.25 : 0.75))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(option.label)
            Spacer()
            Text(option.countDisplayText)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TagMatchModeControl: View {
    @Binding var filters: SearchFilterStateSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(L10n.string("Tag match mode"), selection: Binding(
                get: { filters.tagMatchMode },
                set: { filters = SearchFilterEditing.settingTagMatchMode($0, in: filters) }
            )) {
                Text(L10n.string("Any")).tag(SearchTagMatchModeSnapshot.any)
                Text(L10n.string("All")).tag(SearchTagMatchModeSnapshot.all)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(L10n.string("Tag match mode"))
            .accessibilityValue(filters.tagMatchMode.accessibilityText)
            if filters.tags.count == 1 {
                Text(L10n.string("Any and All match the same single selected tag."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        L10n.format("search.facet.count", label, disabled ? 0 : count)
    }
}

extension SearchStorageModeFacetCountSnapshot {
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
        L10n.format("search.facet.count", label, disabled ? 0 : count)
    }
}
