import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FileDropAdapter {
    let onDrop: ([URL]) -> Void

    func handle(_ providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = Self.fileURLProviders(from: providers)
        guard !fileURLProviders.isEmpty else { return false }

        Self.loadFileURLs(from: fileURLProviders) { urls in
            onDrop(urls)
        }
        return true
    }

    static func fileURLProviders(from providers: [NSItemProvider]) -> [NSItemProvider] {
        providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    }

    static func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = Self.fileURL(from: item) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }

    static func fileURL(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let url as URL:
            return url.isFileURL ? url : nil
        case let data as Data:
            guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                return nil
            }
            return url
        case let string as String:
            let url = URL(fileURLWithPath: string)
            return url.path.isEmpty ? nil : url
        default:
            return nil
        }
    }
}

extension MainRepositoryContentView {
    func openImportFromCommandPalette() {
        closeCommandPalette()
        onImport()
    }

    func openSettingsFromCommandPalette() {
        closeCommandPalette()
        onOpenSettings()
    }

    func beginSearchFromCommandPalette() {
        closeCommandPalette()
        beginCommandFindSearch()
    }

    func openBatchAddTagsFromCommandPalette() {
        let route = commandPaletteBatchAddTagsRoute()
        pendingBatchAddTagsRoute = route
        closeCommandPalette()
    }

    func openBatchChangeCategoryFromCommandPalette() {
        let route = commandPaletteBatchChangeCategoryRoute()
        pendingBatchChangeCategoryRoute = route
        closeCommandPalette()
    }

    func openBatchDeleteFromCommandPalette() {
        pendingBatchDeleteRoute = commandPaletteBatchDeleteRoute()
        closeCommandPalette()
    }

    func openBatchRenameFromCommandPalette() {
        pendingBatchRenameRoute = commandPaletteBatchRenameRoute()
        closeCommandPalette()
    }

    func focusFileFromCommandPalette(_ fileID: Int64) {
        selectedFileIDs = [fileID]
        closeCommandPalette()
        Task { await fileListModel.selectFiles([fileID]) }
    }

    func openRepositoryFromCommandPalette() {
        closeCommandPalette()
        onOpenRepository()
    }

    func openHelpFromCommandPalette() {
        closeCommandPalette()
        onOpenHelp()
    }

    func openClassifierRuleEditorFromCommandPalette() {
        fileListModel.clearCommandPaletteState()
        fileListModel.commandPaletteQuery = ""
        fileListModel.pendingSearchDestination = .classifierRuleEditor(context: nil)
    }

    var dropOverlay: some View {
        Group {
            if let presentation = dropPreviewModel.presentation {
                DropZoneOverlay(presentation: presentation)
                    .padding(24)
            }
        }
    }

    @ViewBuilder
    func contextMenu(for selection: Set<Int64>) -> some View {
        let selectedFiles = files(for: selection)
        if selectedFiles.count == 1, let file = selectedFiles.first {
            singleFileContextMenu(for: file)
        } else {
            multiFileContextMenu(for: selection, selectedFiles: selectedFiles)
        }
    }

    @ViewBuilder
    private func singleFileContextMenu(for file: FileEntrySnapshot) -> some View {
        Button("Show in Finder") {
            onShowInFinder(file.path)
        }
        Button("Rename...") {
            fileListModel.beginRename(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Button("Change Category...") {
            fileListModel.beginChangeCategory(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Button("Correct Classification...") {
            fileListModel.beginClassifierCorrection(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Button("Delete...", role: .destructive) {
            fileListModel.beginDelete(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Divider()
        Button("Copy Path") {
            onCopyPath(file.path)
        }
    }

    @ViewBuilder
    private func multiFileContextMenu(for selection: Set<Int64>, selectedFiles: [FileEntrySnapshot]) -> some View {
        if selectedFiles.count > 1 {
            Button("Add tags...") {
                openBatchAddTagsRoute(selection, source: .listContextMenu)
            }
            Button("Change category...") {
                openBatchChangeCategoryRoute(selection, source: .listContextMenu)
            }
            Button("Rename...") {
                openBatchRenameRoute(selection, source: .listContextMenu)
            }
            Button("Delete...", role: .destructive) {
                openBatchDeleteRoute(selection, source: .listContextMenu)
            }
        }
        Button("Copy Paths") {
            onCopyPaths(selectedFiles.map(\.path))
        }
        .disabled(selectedFiles.isEmpty)
    }

    func files(for selection: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { selection.contains($0.id) }
    }

    var fileTable: some View {
        VStack(spacing: 8) {
            ImportProgressTableView(rows: importProgressRows, selection: $selectedImportProgressIDs)
            fileTableContent
        }
        .overlay { emptyListOverlay }
    }

    private var fileTableContent: some View {
        Table(visibleFiles, selection: $selectedFileIDs, sortOrder: $tableSortOrder) {
            TableColumn("Name", sortUsing: KeyPathComparator(\FileEntrySnapshot.currentName)) { file in
                Text(file.currentName)
                    .lineLimit(1)
            }
            TableColumn("Category / Path", sortUsing: KeyPathComparator(\FileEntrySnapshot.path)) { file in
                Text(file.categoryPathDisplay)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Match") { file in
                Text(searchMatchText(for: file.id))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Size", sortUsing: KeyPathComparator(\FileEntrySnapshot.sizeBytes)) { file in
                Text(file.sizeDisplay)
                    .monospacedDigit()
            }
            TableColumn("Modified", sortUsing: KeyPathComparator(\FileEntrySnapshot.updatedAt)) { file in
                Text(file.updatedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn("Imported", sortUsing: KeyPathComparator(\FileEntrySnapshot.importedAt)) { file in
                Text(file.importedAtDisplay)
                    .monospacedDigit()
            }
            TableColumn("Status", sortUsing: KeyPathComparator(\FileEntrySnapshot.statusDisplay)) { file in
                Text(file.statusDisplay)
            }
        }
        .contextMenu(forSelectionType: Int64.self) { selection in
            contextMenu(for: selection)
        } primaryAction: { selection in
            selectedFileIDs = selection
        }
    }

    @ViewBuilder
    func searchRouteStatus(_ destination: MainSearchDestination) -> some View {
        switch destination {
        case let .searchEmpty(request):
            SearchEmptyRouteView(
                request: request,
                indexStatus: fileListModel.searchState.indexStatus,
                onClearSearch: clearSearchQuery,
                onClearFilters: clearSearchFiltersFromEmptyState,
                onRemoveFilter: removeSearchFilterFromEmptyState,
                onSearchAllFileTypes: searchAllFileTypesFromEmptyState
            )
        case let .queryError(request, diagnostic):
            QueryErrorRouteView(
                request: request,
                diagnostic: diagnostic,
                onApplySuggestion: applyQuerySuggestion,
                onClear: clearSearch
            )
        case .savedSearchSheet, .indexingStatus, .commandPalette, .classifierRuleEditor:
            EmptyView()
        }
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
            Text("Filter by tags")
                .font(.callout.weight(.semibold))
            TextField("Search tags", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .accessibilityIdentifier("S2-08-tag-search")
            SelectedTagChips(filters: $filters, tagFacets: tagOptions)
            TagMatchModeControl(filters: $filters)
            tagList
            tagFooter
        }
        .accessibilityIdentifier("S2-08-tags-filter")
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
            Text("Loading tags...")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if tagOptions.isEmpty {
            tagEmptyState
        } else if visibleTagOptions.isEmpty {
            Text("No matching tags")
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
            Button("Clear all") {
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
            Button("Retry tags", action: onRetryTagRegistry)
                .font(.caption)
        } else if facetsState.errorMapping != nil, !tagOptions.isEmpty {
            Button("Retry counts", action: onRetry)
                .font(.caption)
        } else if isLoadingTags, !tagOptions.isEmpty {
            Text("Loading tags...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func tagLoadingFailure(error: CoreErrorMappingSnapshot, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text("Could not load tags")
            Button("Retry", action: retry)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Could not load tags. \(error.userMessage)")
    }

    private var tagEmptyState: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("No tags yet")
            Text("Add tags from file detail or batch actions.")
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
                        Button {
                            filters = SearchFilterEditing.removingTag(tag, from: filters)
                        } label: {
                            Label(label(for: tag), systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Remove tag filter \(label(for: tag))")
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

private struct TagMatchModeControl: View {
    @Binding var filters: SearchFilterStateSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Tag match mode", selection: Binding(
                get: { filters.tagMatchMode },
                set: { filters = SearchFilterEditing.settingTagMatchMode($0, in: filters) }
            )) {
                Text("Any").tag(SearchTagMatchModeSnapshot.any)
                Text("All").tag(SearchTagMatchModeSnapshot.all)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Tag match mode")
            .accessibilityValue(filters.tagMatchMode.accessibilityText)
            if filters.tags.count == 1 {
                Text("Any and All match the same single selected tag.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
