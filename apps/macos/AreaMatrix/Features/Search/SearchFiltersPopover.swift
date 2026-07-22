import SwiftUI

struct SearchFiltersPopover: View {
    @Binding var filters: SearchFilterStateSnapshot
    var facetsState: MainSearchFacetsState
    var tagRegistryState: TagFilterRegistryState
    var tagRegistryAnchorFileID: Int64?
    var canSaveAsSmartList: Bool
    var isEditingSmartListDraft: Bool
    var saveDisabledReason: String?
    var onReset: () -> Void
    var onRetry: () -> Void
    var onLoadTagRegistry: (Int64?) -> Void
    var onRetryTagRegistry: () -> Void
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
            Label(L10n.format("search.filters.loadError", error.userMessage), systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if facetsState.isLoading {
            Label("Loading filter counts...", systemImage: "clock.arrow.circlepath")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let facets = facetsState.facets {
            Label(L10n.plural("search.matchingFileCount", count: facets.totalCount), systemImage: "number")
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
                title: L10n.string("Category"),
                allLabel: L10n.string("All categories"),
                selection: $filters.category,
                options: facetsState.facets?.categories ?? [],
                isLoading: facetsState.isLoading,
                emptyMessage: L10n.string("No categories yet")
            )
            SearchFacetPicker(
                title: L10n.string("Type"),
                allLabel: L10n.string("All types"),
                selection: $filters.fileKind,
                options: facetsState.facets?.fileKinds ?? [],
                isLoading: facetsState.isLoading,
                emptyMessage: L10n.string("No file types yet")
            )
            SearchTagFacetPicker(
                filters: $filters,
                facetsState: facetsState,
                tagRegistryState: tagRegistryState,
                tagRegistryAnchorFileID: tagRegistryAnchorFileID,
                onRetry: onRetry,
                onLoadTagRegistry: onLoadTagRegistry,
                onRetryTagRegistry: onRetryTagRegistry
            )
            SearchDateFilterSection(
                title: L10n.string("Modified"),
                field: .modified,
                bounds: facetsState.facets?.dateBounds,
                filters: $filters
            )
            SearchDateFilterSection(
                title: L10n.string("Imported"),
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
            if isEditingSmartListDraft {
                Text("Draft changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let saveDisabledReason, !canSaveAsSmartList {
                Text(saveDisabledReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Retry", action: onRetry)
                .disabled(facetsState.errorMapping == nil)
            if !isEditingSmartListDraft {
                Button("Save as Smart List", action: onSaveAsSmartList)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSaveAsSmartList)
            }
            Button("Close") { dismiss() }
        }
    }

    private var activeSummary: String {
        let count = facetsState.facets?.activeFilterCount ?? filters.activeFilterCount
        return L10n.plural("search.activeFilterCount", count: count)
    }
}
