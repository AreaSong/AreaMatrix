import SwiftUI

struct SearchFilterChipsBar: View {
    @Binding var filters: SearchFilterStateSnapshot

    var body: some View {
        let chips = SearchFilterChips.items(for: filters)
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        SearchFilterChipButton(
                            title: chip.label,
                            accessibilityLabel: "Remove filter \(chip.label)"
                        ) {
                            filters = SearchFilterEditing.removing(chip.kind, from: filters)
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(chips.count) active filters")
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
                        SearchFilterChipButton(
                            title: label(for: tag),
                            accessibilityLabel: "Remove tag filter \(label(for: tag))"
                        ) {
                            filters = SearchFilterEditing.removingTag(tag, from: filters)
                        }
                    }
                }
            }
            .accessibilityLabel("Selected tags \(filters.tags.joined(separator: ", "))")
        }
    }

    private func label(for tag: String) -> String {
        tagFacets.first { $0.value.caseInsensitiveCompare(tag) == .orderedSame }?.label ?? tag
    }
}

struct SearchFilterChipButton: View {
    let title: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
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
        fileListModel: MainFileListModel
    ) {
        if fileListModel.isEditingSmartListFilterDraft {
            fileListModel.updateSmartListFilterDraft(filters)
            return
        }
        searchFilters = filters
    }
}
