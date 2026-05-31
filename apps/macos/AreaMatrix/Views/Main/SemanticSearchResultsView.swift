import SwiftUI

struct SemanticSearchResultsView: View {
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
                    title: "Semantic matches",
                    count: page.semanticTotalCount,
                    rows: page.semanticRows(),
                    emptyText: "No semantic matches. Normal search results are shown below.",
                    selectedFileIDs: selectedFileIDs,
                    loadingMore: pagingState.isLoadingSemantic,
                    loadMoreTitle: "Load more semantic",
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
        .accessibilityIdentifier("S3-08-semantic-search-results")
    }

    private var normalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if page.dedupedNormalCount > 0 {
                Button(showFoldedDuplicates ? "Hide duplicate normal matches" : "Show duplicate normal matches") {
                    onToggleDuplicates()
                }
                .accessibilityIdentifier("S3-08-show-duplicate-normal-matches")
            }
            SemanticSearchGroupView(
                title: "Normal search matches",
                count: page.normalTotalCount,
                rows: page.normalRows(showFoldedDuplicates: showFoldedDuplicates),
                emptyText: "No normal matches. Semantic matches are shown above.",
                selectedFileIDs: selectedFileIDs,
                loadingMore: pagingState.isLoadingNormal,
                loadMoreTitle: "Load more normal",
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
            TableColumn("Name") { row in
                Text(row.file.currentName)
                    .lineLimit(1)
            }
            TableColumn("Path") { row in
                Text(row.categoryPath)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Category") { row in
                Text(row.file.category)
                    .lineLimit(1)
            }
            TableColumn("Match source") { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.matchSource)
                    if row.alsoMatchedNormalSearch {
                        Text("Also matched normal search")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if row.isFoldedDuplicate {
                        Text("Duplicate normal match")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            TableColumn("Relevance") { row in
                Text(row.relevance)
                    .monospacedDigit()
            }
            TableColumn("Matched reason") { row in
                DisclosureGroup("Why this matched") {
                    Text(row.whyThisMatched)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            TableColumn("Modified") { row in
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
                Button("Retry page", action: onRetryPage)
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
                .accessibilityIdentifier("S3-08-\(loadMoreTitle.lowercased().replacingOccurrences(of: " ", with: "-"))")
        }
    }
}
