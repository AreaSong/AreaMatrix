import SwiftUI

struct SemanticSearchResultsView: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let page: SemanticSearchResultPageSnapshot
    let selectedFileIDs: Binding<Set<Int64>>
    let showFoldedDuplicates: Bool
    let pagingState: SemanticSearchPagingState
    let onToggleDuplicates: () -> Void
    let onLoadMoreSemantic: () -> Void
    let onLoadMoreNormal: () -> Void
    let onRetrySemanticPage: () -> Void
    let onRetryNormalPage: () -> Void
    let contextMenu: (Set<Int64>) -> AnyView
    let onPrimaryAction: (Set<Int64>) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SemanticSearchGroupView(
                    title: L10n.string("Semantic matches"),
                    count: page.semanticTotalCount,
                    rows: page.semanticRows(),
                    emptyText: L10n.string("No semantic matches. Normal search results are shown below."),
                    selectedFileIDs: selectedFileIDs,
                    loadingMore: pagingState.isLoadingSemantic,
                    loadMoreTitle: L10n.string("Load more semantic"),
                    hasMore: page.hasMoreSemanticMatches,
                    pageError: pagingState.semanticError,
                    onLoadMore: onLoadMoreSemantic,
                    onRetryPage: onRetrySemanticPage,
                    contextMenu: contextMenu,
                    onPrimaryAction: onPrimaryAction
                )
                normalSection
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("semantic-search-semantic-search-results")
    }

    private var normalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if page.dedupedNormalCount > 0 {
                Button(
                    showFoldedDuplicates
                        ? L10n.string("Hide duplicate normal matches")
                        : L10n.string("Show duplicate normal matches")
                ) {
                    onToggleDuplicates()
                }
                .accessibilityIdentifier("semantic-search-show-duplicate-normal-matches")
            }
            SemanticSearchGroupView(
                title: L10n.string("Normal search matches"),
                count: page.normalTotalCount,
                rows: page.normalRows(showFoldedDuplicates: showFoldedDuplicates),
                emptyText: L10n.string("No normal matches. Semantic matches are shown above."),
                selectedFileIDs: selectedFileIDs,
                loadingMore: pagingState.isLoadingNormal,
                loadMoreTitle: L10n.string("Load more normal"),
                hasMore: page.hasMoreNormalMatches,
                pageError: pagingState.normalError,
                onLoadMore: onLoadMoreNormal,
                onRetryPage: onRetryNormalPage,
                contextMenu: contextMenu,
                onPrimaryAction: onPrimaryAction
            )
        }
    }
}

private struct SemanticSearchGroupView: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let title: String
    let count: Int64
    let rows: [SemanticSearchRowPresentation]
    let emptyText: String
    let selectedFileIDs: Binding<Set<Int64>>
    let loadingMore: Bool
    let loadMoreTitle: String
    let hasMore: Bool
    let pageError: CoreErrorMappingSnapshot?
    let onLoadMore: () -> Void
    let onRetryPage: () -> Void
    let contextMenu: (Set<Int64>) -> AnyView
    let onPrimaryAction: (Set<Int64>) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title) (\(count))")
                .font(.callout.weight(.semibold))
            if rows.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                table
            }
            footer
        }
        .accessibilityElement(children: .contain)
    }

    private var table: some View {
        Table(rows, selection: selectedFileIDs) {
            TableColumn(L10n.string("Name")) { row in
                Text(row.file.currentName)
                    .lineLimit(1)
            }
            TableColumn(L10n.string("Path")) { row in
                Text(row.categoryPath)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn(L10n.string("Category")) { row in
                Text(row.file.category)
                    .lineLimit(1)
            }
            TableColumn(L10n.string("Match source")) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.resolve(row.matchSource))
                    if row.alsoMatchedNormalSearch {
                        Text(L10n.string("Also matched normal search"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if row.isFoldedDuplicate {
                        Text(L10n.string("Duplicate normal match"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn(L10n.string("Relevance")) { row in
                Text(row.relevance)
                    .monospacedDigit()
            }
            TableColumn(L10n.string("Matched reason")) { row in
                DisclosureGroup(L10n.string("Why this matched")) {
                    Text(row.whyThisMatched.resolve(using: localizer))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            TableColumn(L10n.string("Modified")) { row in
                Text(row.modified)
                    .monospacedDigit()
            }
        }
        .frame(minHeight: 160)
        .contextMenu(forSelectionType: Int64.self) { selection in
            contextMenu(selection)
        } primaryAction: { selection in
            onPrimaryAction(selection)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let pageError {
            HStack(spacing: 10) {
                Text(pageError.userMessage)
                    .foregroundStyle(.red)
                Button(L10n.string("Retry page"), action: onRetryPage)
            }
            .font(.callout)
        } else if loadingMore {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(loadMoreTitle.replacingOccurrences(of: "Load", with: "Loading"))
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        } else if hasMore {
            Button(loadMoreTitle, action: onLoadMore)
                .accessibilityIdentifier(
                    "semantic-search-\(loadMoreTitle.lowercased().replacingOccurrences(of: " ", with: "-"))"
                )
        }
    }
}
