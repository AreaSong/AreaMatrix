import SwiftUI

extension MainRepositoryContentView {
    @ViewBuilder
    var mainRepositorySearchStatusBanner: some View {
        if let request = fileListModel.searchState.request {
            VStack(alignment: .leading, spacing: 6) {
                mainRepositorySearchBannerHeader(request)
                mainRepositorySearchBannerDetail
                if !searchFilterSummaryText.isEmpty {
                    Text(searchFilterSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                SearchFilterChipsBar(filters: searchFiltersBinding)
            }
            .padding(10)
            .background(mainRepositorySearchBannerBackground)
        }
    }

    private func mainRepositorySearchBannerHeader(_ request: SearchQueryRequestSnapshot) -> some View {
        HStack(spacing: 10) {
            Label(mainRepositorySearchBannerText(request), systemImage: mainRepositorySearchBannerSystemImage)
                .font(.callout)
            Spacer()
            Button("Retry") {
                Task { await fileListModel.retrySearch() }
            }
            .opacity(mainRepositorySearchRetryOpacity)
            .disabled(mainRepositorySearchRetryDisabled)
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
    }

    private func mainRepositorySearchBannerText(_ request: SearchQueryRequestSnapshot) -> String {
        [
            fileListModel.searchBannerContextText(for: request),
            "范围：\(request.scope.bannerDisplayName)",
            "模式：\(request.mode.displayName)",
            "结果：\(mainRepositorySearchResultCountText)",
            "过滤：\(searchActiveFilterCount)"
        ].joined(separator: "  ")
    }

    private var mainRepositorySearchResultCountText: String {
        guard let page = fileListModel.searchState.page else { return "-" }
        if let semanticPage = page.semanticPage {
            return "\(semanticPage.semanticTotalCount) semantic / \(semanticPage.normalTotalCount) normal"
        }
        return "\(page.totalCount)"
    }

    private var mainRepositorySearchBannerSystemImage: String {
        switch fileListModel.searchState.indexStatus {
        case .unavailable:
            "exclamationmark.triangle"
        case .indexing:
            "clock.arrow.circlepath"
        default:
            "magnifyingglass"
        }
    }

    private var mainRepositorySearchRetryOpacity: Double {
        fileListModel.searchState.errorMapping == nil &&
            fileListModel.searchState.indexStatus != .unavailable ? 0 : 1
    }

    private var mainRepositorySearchRetryDisabled: Bool {
        fileListModel.searchState.errorMapping == nil &&
            fileListModel.searchState.indexStatus != .unavailable
    }

    private var mainRepositorySearchBannerBackground: Color {
        if fileListModel.searchState.errorMapping != nil ||
            fileListModel.searchState.indexStatus == .unavailable {
            return Color.red.opacity(0.12)
        }
        return Color.blue.opacity(0.08)
    }

    @ViewBuilder
    private var mainRepositorySearchBannerDetail: some View {
        if let error = fileListModel.searchState.errorMapping {
            Text("Search failed: \(error.userMessage)")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let semanticPage = fileListModel.searchState.page?.semanticPage {
            semanticBannerDetail(semanticPage)
        } else {
            searchFallbackBannerDetail
        }
    }

    @ViewBuilder
    private var searchFallbackBannerDetail: some View {
        if fileListModel.searchState.indexStatus == .unavailable {
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
            mainRepositorySearchMatchSummary(result)
        }
    }

    @ViewBuilder
    private func mainRepositorySearchMatchSummary(_ result: SearchFileResultSnapshot) -> some View {
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
}
