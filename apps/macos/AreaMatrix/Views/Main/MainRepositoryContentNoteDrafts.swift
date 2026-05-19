import Foundation
import SwiftUI

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
            searchScope.rawValue,
            searchSort.rawValue,
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
            Text(fileListModel.searchState.isActive ? "No search results" : "No files in this category")
                .foregroundStyle(.secondary)
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
            detailTabRequest: fileListModel.detailTabRequest,
            selectedImportProgressRow: selectedImportProgressRow,
            onRetrySelectedFileDetail: {
                Task {
                    await fileListModel.retrySelectedFileDetail()
                }
            },
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
            onBeginDeleteFile: fileListModel.beginDelete,
            onBeginICloudConflictResolution: fileListModel.beginICloudConflictResolution,
            writeActionDisabledReason: fileListModel.writeActionDisabledReason,
            noteModel: detailNoteModel
        )
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
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
                    Button("Clear") {
                        clearSearch()
                    }
                }
                searchBannerDetail
            }
            .padding(10)
            .background(searchBannerBackground)
        }
    }

    private func searchBannerText(_ request: SearchQueryRequestSnapshot) -> String {
        "搜索：\"\(request.query)\"  范围：\(request.scope.bannerDisplayName)  结果：\(searchResultCountText)"
    }

    private var searchResultCountText: String {
        guard let page = fileListModel.searchState.page else { return "-" }
        return "\(page.totalCount)"
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
        } else if fileListModel.searchState.indexStatus == .unavailable {
            Text("Search index unavailable")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if fileListModel.searchState.isLoading {
            Text("Searching...")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let diagnostic = fileListModel.searchState.page?.diagnostics.first {
            Text("\(diagnostic.severityDisplayName): \(diagnostic.message)")
                .font(.callout)
                .foregroundStyle(.secondary)
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
        fileListModel.clearSearch()
        selectedFileIDs = []
        searchScope = selectedSidebarRow.categoryForFileList == nil ? .all : .current
        Task {
            await fileListModel.loadCurrentCategory(selectedSidebarRow.categoryForFileList)
        }
    }
}
