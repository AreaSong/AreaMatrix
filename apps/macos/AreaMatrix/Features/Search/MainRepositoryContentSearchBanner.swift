import SwiftUI

extension MainRepositoryContentView {
    @ViewBuilder
    var mainRepositorySearchStatusBanner: some View {
        if let request = searchModel.searchState.request {
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
            Button(L10n.string("Retry")) {
                Task { await searchModel.retrySearch() }
            }
            .opacity(mainRepositorySearchRetryOpacity)
            .disabled(mainRepositorySearchRetryDisabled)
            Button(searchFiltersButtonTitle) {
                searchModel.routingState.isToolbarFiltersPresented.toggle()
            }
            Button(L10n.string("Save..."), action: searchModel.openSavedSearchSheet)
                .disabled(!searchModel.canSaveCurrentSearch)
            smartListBannerEditButton
            Button(L10n.string("Clear")) {
                clearSearch()
            }
        }
    }

    private func mainRepositorySearchBannerText(_ request: SearchQueryRequestSnapshot) -> String {
        [
            searchModel.searchBannerContextText(for: request),
            L10n.format("search.banner.scope", request.scope.bannerDisplayName),
            L10n.format("search.banner.mode", request.mode.displayName),
            L10n.format("search.banner.results", mainRepositorySearchResultCountText),
            L10n.format("search.banner.filters", searchActiveFilterCount)
        ].joined(separator: "  ")
    }

    private var mainRepositorySearchResultCountText: String {
        guard let page = searchModel.searchState.page else { return "-" }
        if let semanticPage = page.semanticPage {
            return L10n.format(
                "search.banner.semantic-normal-count",
                semanticPage.semanticTotalCount,
                semanticPage.normalTotalCount
            )
        }
        return "\(page.totalCount)"
    }

    private var mainRepositorySearchBannerSystemImage: String {
        switch searchModel.searchState.indexStatus {
        case .unavailable:
            "exclamationmark.triangle"
        case .indexing:
            "clock.arrow.circlepath"
        default:
            "magnifyingglass"
        }
    }

    private var mainRepositorySearchRetryOpacity: Double {
        searchModel.searchState.errorMapping == nil &&
            searchModel.searchState.indexStatus != .unavailable ? 0 : 1
    }

    private var mainRepositorySearchRetryDisabled: Bool {
        searchModel.searchState.errorMapping == nil &&
            searchModel.searchState.indexStatus != .unavailable
    }

    private var mainRepositorySearchBannerBackground: Color {
        if searchModel.searchState.errorMapping != nil ||
            searchModel.searchState.indexStatus == .unavailable {
            return Color.red.opacity(0.12)
        }
        return Color.blue.opacity(0.08)
    }

    @ViewBuilder
    private var mainRepositorySearchBannerDetail: some View {
        if let error = searchModel.searchState.errorMapping {
            Text(L10n.format("search.failed", error.userMessage))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let semanticPage = searchModel.searchState.page?.semanticPage {
            semanticBannerDetail(semanticPage)
        } else {
            searchFallbackBannerDetail
        }
    }

    @ViewBuilder
    private var searchFallbackBannerDetail: some View {
        if searchModel.searchState.indexStatus == .unavailable {
            HStack(spacing: 10) {
                Text(L10n.string("Search index unavailable"))
                Button(L10n.string("Open indexing status")) {
                    searchModel.openIndexingStatus()
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if searchModel.searchState.isLoading {
            Text(searchLoadingText)
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let diagnostic = searchModel.searchState.page?.diagnostics.first {
            Text(L10n.format("search.diagnostic.summary", diagnostic.severityDisplayName, diagnostic.message))
                .font(.callout)
                .foregroundStyle(diagnostic.isError ? Color.red : Color.secondary)
                .accessibilityHint(diagnostic.problemAccessibilityHint)
        } else if let result = searchModel.searchState.page?.results.first {
            mainRepositorySearchMatchSummary(result)
        }
    }

    @ViewBuilder
    private func mainRepositorySearchMatchSummary(_ result: SearchFileResultSnapshot) -> some View {
        if let noteSnippet = result.noteSnippet {
            Text(L10n.format("mainList.searchMatch.note", noteSnippet))
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let match = result.matches.first {
            Text(L10n.format(
                "mainList.searchMatch.summary",
                match.kindDisplayName,
                match.fieldDisplayName,
                match.snippet
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }
}
