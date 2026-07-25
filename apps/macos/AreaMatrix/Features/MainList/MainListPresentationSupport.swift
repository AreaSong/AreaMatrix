import SwiftUI

extension MainRepositoryContentView {
    var listCountText: String {
        if fileListModel.searchState.isActive {
            let count = fileListModel.searchState.page?.totalCount ?? Int64(visibleFiles.count)
            return L10n.plural("mainList.searchResultCount", count: count)
        }
        return L10n.plural("mainList.filesLoaded", count: visibleFiles.count)
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
            return L10n.format("mainList.searchMatch.note", noteSnippet)
        }
        guard let match = result.matches.first else { return L10n.string("Match") }
        return L10n.format(
            "mainList.searchMatch.summary",
            match.kindDisplayName,
            match.fieldDisplayName,
            match.snippet
        )
    }

    @ViewBuilder
    var emptyListOverlay: some View {
        if !fileListModel.isLoading, visibleFiles.isEmpty, importProgressPresentation.rows.isEmpty {
            if let destination = fileListModel.searchPageDestination {
                searchRouteStatus(destination)
            } else {
                Text(
                    fileListModel.searchState.isActive
                        ? L10n.string("No search results")
                        : L10n.string("No files in this category")
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(16)
                .areaMatrixGlassCard(cornerRadius: 10)
            }
        }
    }

    @ViewBuilder
    var statusBanner: some View {
        if fileListModel.searchState.isActive {
            searchStatusBanner
        } else if let banner = fileListModel.statusBanner {
            TintedStatusBanner(
                tint: .yellow,
                cornerRadius: 0,
                fillsWidth: false,
                contentPadding: 10,
                backgroundOpacity: 0.12
            ) {
                HStack(spacing: 10) {
                    Label(banner.message, systemImage: banner.systemImage)
                        .font(.callout)
                    Spacer()
                    Button(L10n.string("Retry")) {
                        Task {
                            await fileListModel.retryCurrentCategory()
                        }
                    }
                    Button(L10n.string("Dismiss")) {
                        fileListModel.clearStatusBanner()
                    }
                }
            }
        } else if state == .list {
            SyncConflictEntryPanel(model: syncConflictEntryModel) { route in
                syncConflictReviewRoutingState.route = route
            }
        }
    }
}
