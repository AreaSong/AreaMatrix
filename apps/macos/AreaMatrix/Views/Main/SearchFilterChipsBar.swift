import SwiftUI

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
