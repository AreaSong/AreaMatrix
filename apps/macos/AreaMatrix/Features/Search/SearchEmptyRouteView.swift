import SwiftUI

struct SearchEmptyRouteView: View {
    let request: SearchQueryRequestSnapshot
    var indexStatus: SearchIndexStatusSnapshot? = .ready
    let onClearSearch: () -> Void
    let onClearFilters: () -> Void
    let onRemoveFilter: (SearchFilterChipKind) -> Void
    let onSearchAllFileTypes: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 14) {
            Label("No files found", systemImage: "magnifyingglass")
                .font(.title3.weight(.semibold))
            Text(reasonText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            conditionSummary
            actionButtons
            if shouldShowFilterShortcuts {
                filterShortcutButtons
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-empty-search-empty")
    }

    private var conditionSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Query: \(querySummary)")
            Text("Filters: \(filterSummary)")
            Text(searchContextText(request))
            if indexStatus == .indexing {
                Text("Indexing...")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 360, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search conditions. Query \(querySummary). Filters \(filterSummary).")
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if request.filters.isEmpty {
                Button("Clear search", action: onClearSearch)
                    .keyboardShortcut(.cancelAction)
            } else {
                Button("Clear filters", action: onClearFilters)
                    .keyboardShortcut(.defaultAction)
                Button("Clear search", action: onClearSearch)
            }
        }
    }

    private var filterShortcutButtons: some View {
        VStack(alignment: .center, spacing: 8) {
            if request.filters.fileKind != nil {
                Button("Search all file types", action: onSearchAllFileTypes)
            }
            ForEach(SearchFilterChips.items(for: request.filters)) { chip in
                Button(L10n.format("search.filter.remove", chip.label)) {
                    onRemoveFilter(chip.kind)
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .accessibilityElement(children: .contain)
    }

    private var reasonText: String {
        if indexStatus == .indexing {
            return L10n.string("Search is still indexing. Results may appear in a moment.")
        }
        if !request.query.isEmpty, request.filters.activeFilterCount > 0 {
            return L10n.format("search.empty.queryAndFilters", activeFilterText)
        }
        if !request.query.isEmpty {
            return L10n.format("search.empty.query", request.query)
        }
        return L10n.format("search.empty.filters", activeFilterText)
    }

    private var shouldShowFilterShortcuts: Bool {
        request.filters.activeFilterCount > 0 && indexStatus != .indexing
    }

    private var querySummary: String {
        request.query.isEmpty ? L10n.string("None") : request.query
    }

    private var filterSummary: String {
        let chips = SearchFilterChips.items(for: request.filters).map(\.label)
        return chips.isEmpty ? L10n.string("None") : chips.joined(separator: ", ")
    }

    private var activeFilterText: String {
        let count = request.filters.activeFilterCount
        return L10n.plural("search.activeFilterCount", count: count)
    }
}
