import AreaMatrixUIFoundation
import SwiftUI

struct SearchFilterChipsBar: View {
    @Binding var filters: SearchFilterStateSnapshot

    var body: some View {
        let chips = SearchFilterChips.items(for: filters)
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        FilterChipButton(
                            title: chip.label,
                            accessibilityLabel: L10n.format("search.filter.remove.accessibilityLabel", chip.label)
                        ) {
                            filters = SearchFilterEditing.removing(chip.kind, from: filters)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L10n.plural("search.activeFilterCount", count: chips.count))
        }
    }
}

struct SelectedTagChips: View {
    @Binding var filters: SearchFilterStateSnapshot
    var tagFacets: [SearchFacetCountSnapshot]

    var body: some View {
        if filters.tags.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters.tags, id: \.self) { tag in
                        FilterChipButton(
                            title: label(for: tag),
                            accessibilityLabel: L10n.format(
                                "search.tagFilter.remove.accessibilityLabel",
                                label(for: tag)
                            )
                        ) {
                            filters = SearchFilterEditing.removingTag(tag, from: filters)
                        }
                    }
                }
            }
            .accessibilityLabel(L10n.format("Selected tags %@", filters.tags.joined(separator: ", ")))
        }
    }

    private func label(for tag: String) -> String {
        tagFacets.first { $0.value.caseInsensitiveCompare(tag) == .orderedSame }?.label ?? tag
    }
}

enum SearchFilterStateRouting {
    static func effective(
        searchFilters: SearchFilterStateSnapshot,
        draft: SmartListFilterDraft?
    ) -> SearchFilterStateSnapshot {
        draft?.filters ?? searchFilters
    }

    @MainActor
    static func assign(
        _ filters: SearchFilterStateSnapshot,
        searchFilters: inout SearchFilterStateSnapshot,
        searchModel: SearchModel
    ) {
        if searchModel.isEditingSmartListFilterDraft {
            searchModel.updateSmartListFilterDraft(filters)
            return
        }
        searchFilters = filters
    }
}
