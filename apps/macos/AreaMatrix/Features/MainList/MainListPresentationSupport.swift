import SwiftUI

extension MainRepositoryContentView {
    var listCountText: String {
        if fileListModel.searchState.isActive {
            return "\(fileListModel.searchState.page?.totalCount ?? Int64(visibleFiles.count)) results"
        }
        return "\(visibleFiles.count) files"
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
                    Button("Retry") {
                        Task {
                            await fileListModel.retryCurrentCategory()
                        }
                    }
                    Button("Dismiss") {
                        fileListModel.clearStatusBanner()
                    }
                }
            }
        } else if state == .list {
            SyncConflictEntryPanel(model: syncConflictEntryModel) { route in
                pendingSyncConflictReviewRoute = route
            }
        }
    }
}
