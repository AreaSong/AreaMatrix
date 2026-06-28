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
            if let semanticPage = fileListModel.searchState.page?.semanticPage {
                semanticResultsContent(semanticPage)
            } else {
                fileTableContent
            }
        }
        .overlay { emptyListOverlay }
    }

    private func semanticResultsContent(_ page: SemanticSearchResultPageSnapshot) -> some View {
        SemanticSearchResultsView(
            page: page,
            selectedFileIDs: $selectedFileIDs,
            showFoldedDuplicates: fileListModel.showFoldedSemanticDuplicates,
            pagingState: fileListModel.semanticPagingState,
            onToggleDuplicates: fileListModel.toggleFoldedSemanticDuplicates,
            onLoadMoreSemantic: {
                Task { await fileListModel.loadMoreSemanticMatches(.semantic) }
            },
            onLoadMoreNormal: {
                Task { await fileListModel.loadMoreSemanticMatches(.normal) }
            },
            onRetrySemanticPage: {
                Task { await fileListModel.loadMoreSemanticMatches(.semantic) }
            },
            onRetryNormalPage: {
                Task { await fileListModel.loadMoreSemanticMatches(.normal) }
            },
            contextMenu: { selection in AnyView(contextMenu(for: selection)) },
            onPrimaryAction: { selection in selectedFileIDs = selection }
        )
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
