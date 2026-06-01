import Foundation

// swiftlint:disable file_length
import SwiftUI

enum SearchFilterChipKind: String, Equatable {
    case category
    case fileKind
    case tags
    case importedDate
    case modifiedDate
    case storage
    case includeDeleted
}

struct SearchFilterChip: Identifiable, Equatable {
    var kind: SearchFilterChipKind
    var label: String

    var id: SearchFilterChipKind {
        kind
    }
}

enum SearchFilterChips {
    static func items(for filters: SearchFilterStateSnapshot) -> [SearchFilterChip] {
        var chips: [SearchFilterChip] = []
        append(filters.category, kind: .category, prefix: "Category", to: &chips)
        append(filters.fileKind, kind: .fileKind, prefix: "Type", to: &chips)
        if !filters.tags.isEmpty {
            chips.append(SearchFilterChip(kind: .tags, label: "tag:\(filters.tags.joined(separator: ","))"))
        }
        appendDate(.modified, filters: filters, kind: .modifiedDate, title: "Modified", to: &chips)
        appendDate(.imported, filters: filters, kind: .importedDate, title: "Imported", to: &chips)
        if let storageMode = filters.storageMode {
            chips.append(SearchFilterChip(kind: .storage, label: "Storage: \(storageMode.displayName)"))
        }
        if filters.includeDeleted {
            chips.append(SearchFilterChip(kind: .includeDeleted, label: "Include deleted"))
        }
        return chips
    }

    private static func append(
        _ value: String?,
        kind: SearchFilterChipKind,
        prefix: String,
        to chips: inout [SearchFilterChip]
    ) {
        guard let value, !value.isEmpty else { return }
        chips.append(SearchFilterChip(kind: kind, label: "\(prefix): \(value)"))
    }

    private static func appendDate(
        _ field: SearchFilterDateField,
        filters: SearchFilterStateSnapshot,
        kind: SearchFilterChipKind,
        title: String,
        to chips: inout [SearchFilterChip]
    ) {
        guard field.afterTimestamp(in: filters) != nil || field.beforeTimestamp(in: filters) != nil else { return }
        chips.append(SearchFilterChip(kind: kind, label: "\(title): \(field.summary(in: filters))"))
    }
}

extension MainRepositoryContentView {
    @MainActor
    func showFailedNoteDraftBannerIfNeeded(leaving previousSelection: Set<Int64>) {
        guard previousSelection.count == 1, let fileID = previousSelection.first else { return }
        guard let failedFileID = detailNoteModel.failedDraftFileIDLeaving(fileID: fileID) else { return }
        fileListModel.showUnsavedNoteDraftPreserved(fileID: failedFileID)
    }

    func showUnsavedNoteDraftPreserved(fileID: Int64) {
        fileListModel.showUnsavedNoteDraftPreserved(fileID: fileID)
    }

    var listCountText: String {
        if fileListModel.searchState.isActive {
            return "\(fileListModel.searchState.page?.totalCount ?? Int64(visibleFiles.count)) results"
        }
        return "\(visibleFiles.count) files"
    }

    var searchTaskKey: String {
        [
            filterText,
            searchMode.rawValue,
            searchScope.rawValue,
            searchSort.rawValue,
            effectiveSearchFilters.taskKey,
            selectedSidebarID
        ].joined(separator: "|")
    }

    var searchFacetsTaskKey: String {
        [
            filterText,
            searchScope.rawValue,
            effectiveSearchFilters.taskKey,
            selectedSidebarID
        ].joined(separator: "|")
    }

    var visibleFiles: [FileEntrySnapshot] {
        if fileListModel.searchState.isActive {
            return fileListModel.files
        }
        return MainListVisibleFileFiltering.visibleFiles(
            from: fileListModel.files,
            sidebarRow: selectedSidebarRow,
            filterText: filterText
        )
        .sorted(using: tableSortOrder)
    }

    func searchMatchText(for fileID: Int64) -> String {
        guard let result = fileListModel.searchState.page?.results.first(where: { $0.file.id == fileID }) else {
            return "-"
        }
        if let semantic = fileListModel.searchState.page?.semanticPage?.result(for: fileID) {
            return semanticMatchText(semantic)
        }
        if let noteSnippet = result.noteSnippet, !noteSnippet.isEmpty {
            return "Note: \(noteSnippet)"
        }
        guard let match = result.matches.first else { return "Match" }
        return "\(match.kindDisplayName): \(match.fieldDisplayName) - \(match.snippet)"
    }

    var importProgressRows: [ImportProgressListRow] {
        importProgressItems.map(ImportProgressListRow.init)
    }

    @ViewBuilder
    var emptyListOverlay: some View {
        if !fileListModel.isLoading, visibleFiles.isEmpty, importProgressRows.isEmpty {
            if let destination = fileListModel.searchPageDestination {
                searchRouteStatus(destination)
            } else {
                Text(fileListModel.searchState.isActive ? "No search results" : "No files in this category")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var statusBanner: some View {
        if fileListModel.searchState.isActive {
            searchStatusBanner
        } else if let banner = fileListModel.statusBanner {
            HStack(spacing: 10) {
                Label(banner.message, systemImage: banner.systemImage)
                    .font(.callout)
                Spacer()
                Button("Retry") {
                    Task {
                        await fileListModel.retryCurrentCategory()
                    }
                }
                Button("Dismiss") {
                    fileListModel.clearStatusBanner()
                }
            }
            .padding(10)
            .background(Color.yellow.opacity(0.12))
        }
    }

    var detailPane: some View {
        MainRepositoryDetailPane(
            selection: fileListModel.selection,
            multiSelectionSummary: MultiSelectionDetailSummary(
                selection: fileListModel.selection,
                files: visibleFiles,
                isUpdating: fileListModel.isLoading || fileListModel.isDetailLoading
            ),
            detailErrorMapping: fileListModel.detailErrorMapping,
            isDetailLoading: fileListModel.isDetailLoading,
            selectedFileDetail: fileListModel.selectedFileDetail,
            noteWriteBlock: fileListModel.selectedFileNoteWriteBlock,
            detailLogState: fileListModel.detailLogState,
            detailLogDiagnosticsState: fileListModel.detailLogDiagnosticsState,
            detailExternalCreateSyncState: fileListModel.detailExternalCreateSyncState,
            detailTagEditorState: fileListModel.detailTagEditorState,
            detailTagSuggestionState: fileListModel.detailTagSuggestionState,
            tagSuggestionPresentationRequest: fileListModel.tagSuggestionPresentationRequest,
            detailTagUndoToast: fileListModel.detailTagUndoToast,
            detailTabRequest: fileListModel.detailTabRequest,
            selectedImportProgressRow: selectedImportProgressRow,
            semanticDetail: semanticDetailPresentationForSelectedFile,
            repoPath: opening.config.repoPath,
            batchTagStore: fileListModel.tagStore,
            batchTagUndoStore: fileListModel.undoActionStore,
            batchTagErrorMapper: fileListModel.errorMapper,
            batchDeleter: fileListModel.batchDeleter, batchCategoryChanger: fileListModel.batchCategoryChanger,
            batchRenamer: batchRenamer,
            categoryRows: repositoryTree.sidebarRows,
            onBatchCategoryApplied: applyBatchCategoryChangeResult,
            onBatchDeleteApplied: applyBatchDeleteResult, onBatchRenameApplied: applyBatchRenameResult,
            onBatchCategoryCreateNewCategory: { handoff in
                openClassifierRuleEditorFromBatchCategory(handoff, route: commandPaletteBatchChangeCategoryRoute())
            },
            onRetrySelectedFileDetail: { Task { await fileListModel.retrySelectedFileDetail() } },
            tagActions: detailTagActions,
            onCopyPaths: onCopyPaths,
            onOpenNoteFile: onOpenNoteFile,
            onRefreshChangeLog: {
                Task {
                    await fileListModel.loadSelectedFileChangeLog()
                }
            },
            onRequestDetailLogDiagnostics: fileListModel.requestDetailLogDiagnosticsPrivacyConfirmation,
            onConfirmDetailLogDiagnostics: {
                Task {
                    await fileListModel.collectDetailLogDiagnostics()
                }
            },
            onCancelDetailLogDiagnostics: fileListModel.cancelDetailLogDiagnosticsPrivacyConfirmation,
            onDetailTabRequestConsumed: fileListModel.consumeDetailTabRequest,
            onBeginRenameFile: fileListModel.beginRename,
            onBeginChangeCategoryFile: fileListModel.beginChangeCategory,
            onBeginClassifierCorrectionFile: fileListModel.beginClassifierCorrection,
            onBeginAIClassificationSuggestionFile: fileListModel.beginAIClassificationSuggestion,
            onBeginDeleteFile: fileListModel.beginDelete,
            onBeginICloudConflictResolution: fileListModel.beginICloudConflictResolution,
            onOpenAISettings: onOpenAISettings,
            writeActionDisabledReason: fileListModel.writeActionDisabledReason,
            summaryExitController: summaryExitController,
            noteModel: detailNoteModel
        )
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
    }

    // swiftlint:disable:next identifier_name
    private var semanticDetailPresentationForSelectedFile: SemanticSearchDetailPresentation? {
        guard let fileID = selectedFileIDs.first, selectedFileIDs.count == 1 else { return nil }
        return fileListModel.searchState.page?.semanticPage?.detailPresentation(for: fileID)
    }

    @ViewBuilder
    private var searchStatusBanner: some View {
        if let request = fileListModel.searchState.request {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Label(searchBannerText(request), systemImage: searchBannerSystemImage)
                        .font(.callout)
                    Spacer()
                    Button("Retry") {
                        Task { await fileListModel.retrySearch() }
                    }
                    .opacity(searchRetryOpacity)
                    .disabled(searchRetryDisabled)
                    Button(searchFiltersButtonTitle) {
                        isSearchFiltersPresented.toggle()
                    }
                    Button("Save...", action: fileListModel.openSavedSearchSheet)
                        .disabled(!fileListModel.canSaveCurrentSearch)
                    smartListBannerEditButton
                    Button("Clear") {
                        clearSearch()
                    }
                }
                searchBannerDetail
                if !searchFilterSummaryText.isEmpty {
                    Text(searchFilterSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SearchFilterChipsBar(filters: searchFiltersBinding)
            }
            .padding(10)
            .background(searchBannerBackground)
        }
    }

    private func searchBannerText(_ request: SearchQueryRequestSnapshot) -> String {
        [
            fileListModel.searchBannerContextText(for: request),
            "范围：\(request.scope.bannerDisplayName)",
            "模式：\(request.mode.displayName)",
            "结果：\(searchResultCountText)",
            "过滤：\(searchActiveFilterCount)"
        ].joined(separator: "  ")
    }

    var searchFiltersButtonTitle: String {
        searchActiveFilterCount > 0 ? "Filters (\(searchActiveFilterCount))" : "Filters"
    }

    var searchFiltersAccessibilityLabel: String {
        "\(searchFiltersButtonTitle), \(searchFilterSummaryText)"
    }

    private var searchResultCountText: String {
        guard let page = fileListModel.searchState.page else { return "-" }
        if let semanticPage = page.semanticPage {
            return "\(semanticPage.semanticTotalCount) semantic / \(semanticPage.normalTotalCount) normal"
        }
        return "\(page.totalCount)"
    }

    private var searchActiveFilterCount: Int64 {
        if let draft = fileListModel.smartListFilterDraft {
            return draft.activeFilterCount
        }
        return fileListModel.searchFacetsState.facets?.activeFilterCount ?? searchFilters.activeFilterCount
    }

    var searchSaveDisabledReason: String? {
        guard !fileListModel.canSaveCurrentSearch else { return nil }
        if fileListModel.searchState.page?.hasDiagnosticError == true {
            return "Fix query syntax before saving"
        }
        if fileListModel.searchState.request == nil {
            return "Enter a query before saving"
        }
        return "Wait for search results"
    }

    private var searchFilterSummaryText: String {
        if fileListModel.isEditingSmartListFilterDraft {
            return "\(searchActiveFilterCount) draft filters active"
        }
        if let error = fileListModel.searchFacetsState.errorMapping {
            return "Could not load filters: \(error.userMessage)"
        }
        if let facets = fileListModel.searchFacetsState.facets {
            return "\(facets.activeFilterCount) filters active, \(facets.totalCount) matching files"
        }
        return "\(searchFilters.activeFilterCount) filters active"
    }

    private var searchBannerSystemImage: String {
        switch fileListModel.searchState.indexStatus {
        case .unavailable:
            "exclamationmark.triangle"
        case .indexing:
            "clock.arrow.circlepath"
        default:
            "magnifyingglass"
        }
    }

    private var searchRetryOpacity: Double {
        fileListModel.searchState.errorMapping == nil &&
            fileListModel.searchState.indexStatus != .unavailable ? 0 : 1
    }

    private var searchRetryDisabled: Bool {
        fileListModel.searchState.errorMapping == nil &&
            fileListModel.searchState.indexStatus != .unavailable
    }

    private var searchBannerBackground: Color {
        if fileListModel.searchState.errorMapping != nil ||
            fileListModel.searchState.indexStatus == .unavailable {
            return Color.red.opacity(0.12)
        }
        return Color.blue.opacity(0.08)
    }

    @ViewBuilder
    private var searchBannerDetail: some View {
        if let error = fileListModel.searchState.errorMapping {
            Text("Search failed: \(error.userMessage)")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let semanticPage = fileListModel.searchState.page?.semanticPage {
            semanticBannerDetail(semanticPage)
        } else if fileListModel.searchState.indexStatus == .unavailable {
            HStack(spacing: 10) {
                Text("Search index unavailable")
                Button("Open indexing status") {
                    fileListModel.openIndexingStatus()
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if fileListModel.searchState.isLoading {
            Text(searchLoadingText)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let diagnostic = fileListModel.searchState.page?.diagnostics.first {
            Text("\(diagnostic.severityDisplayName): \(diagnostic.message)")
                .font(.callout)
                .foregroundStyle(diagnostic.isError ? Color.red : Color.secondary)
                .accessibilityHint(diagnostic.problemAccessibilityHint)
        } else if let result = fileListModel.searchState.page?.results.first {
            searchMatchSummary(result)
        }
    }

    @ViewBuilder
    private func searchMatchSummary(_ result: SearchFileResultSnapshot) -> some View {
        if let noteSnippet = result.noteSnippet {
            Text("Note: \(noteSnippet)")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let match = result.matches.first {
            Text("\(match.kindDisplayName): \(match.fieldDisplayName) - \(match.snippet)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    func clearSearch() {
        filterText = ""
        searchMode = .normal
        searchFilters = .empty
        fileListModel.clearSearch()
        selectedFileIDs = []
        if selectedSmartList != nil { selectedSidebarID = Self.defaultSelectedSidebarID(from: regularSidebarRows) }
        searchScope = selectedSidebarRow.categoryForFileList == nil ? .all : .current
        Task { await fileListModel.loadCurrentCategory(selectedSidebarRow.categoryForFileList) }
    }

    func beginCommandFindSearch() {
        fileListModel.enterSearch(context: .commandFind)
        searchMode = .normal
        searchScope = .all
        isSearchFieldFocused = true
    }

    func handleSearchEscape() {
        if isSearchFiltersPresented {
            isSearchFiltersPresented = false
            return
        }
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearchFieldFocused = false
            return
        }
        clearSearch()
    }

    func resetSearchFilters() {
        if fileListModel.isEditingSmartListFilterDraft {
            fileListModel.updateSmartListFilterDraft(.empty)
            return
        }
        searchFilters = .empty
    }

    var effectiveSearchFilters: SearchFilterStateSnapshot {
        SearchFilterStateRouting.effective(
            searchFilters: searchFilters,
            draft: fileListModel.smartListFilterDraft
        )
    }

    var searchFiltersBinding: Binding<SearchFilterStateSnapshot> {
        Binding(
            get: { effectiveSearchFilters },
            set: { filters in
                SearchFilterStateRouting.assign(
                    filters,
                    searchFilters: &searchFilters,
                    fileListModel: fileListModel
                )
            }
        )
    }

    var searchFiltersButton: some View {
        Button {
            isSearchFiltersPresented.toggle()
        } label: {
            Label(searchFiltersButtonTitle, systemImage: "line.3.horizontal.decrease.circle")
        }
        .popover(isPresented: $isSearchFiltersPresented) {
            SearchFiltersPopover(
                filters: searchFiltersBinding,
                facetsState: fileListModel.searchFacetsState,
                tagRegistryState: fileListModel.tagFilterRegistryState,
                tagRegistryAnchorFileID: tagRegistryAnchorFileID,
                canSaveAsSmartList: !fileListModel.isEditingSmartListFilterDraft && fileListModel.canSaveCurrentSearch,
                isEditingSmartListDraft: fileListModel.isEditingSmartListFilterDraft,
                saveDisabledReason: searchSaveDisabledReason,
                onReset: {
                    resetSearchFilters()
                },
                onRetry: {
                    Task { await fileListModel.retrySearchFacets() }
                },
                onLoadTagRegistry: { fileID in
                    Task { await fileListModel.loadTagFilterRegistry(activeFileID: fileID) }
                },
                onRetryTagRegistry: {
                    Task { await fileListModel.retryTagFilterRegistry() }
                },
                onSaveAsSmartList: {
                    isSearchFiltersPresented = false
                    fileListModel.openSavedSearchSheet()
                }
            )
        }
        .accessibilityLabel(searchFiltersAccessibilityLabel)
    }

    var tagRegistryAnchorFileID: Int64? {
        fileListModel.selection.singleFileID ?? fileListModel.files.first?.id
    }
}
