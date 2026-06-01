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

struct SemanticSearchFallbackStatusRegion: View {
    let page: SemanticSearchResultPageSnapshot
    let state: SemanticFallbackState
    let repoPath: String?
    let isIndexBuildBusy: Bool
    let isPrivacyGateChecking: Bool
    let onAction: (AiFallbackAction) -> Void
    @State private var recoverySheet: SemanticSearchFallbackRecoverySheet?

    init(
        page: SemanticSearchResultPageSnapshot,
        state: SemanticFallbackState,
        repoPath: String? = nil,
        isIndexBuildBusy: Bool,
        isPrivacyGateChecking: Bool,
        onAction: @escaping (AiFallbackAction) -> Void
    ) {
        self.page = page
        self.state = state
        self.repoPath = repoPath
        self.isIndexBuildBusy = isIndexBuildBusy
        self.isPrivacyGateChecking = isPrivacyGateChecking
        self.onAction = onAction
    }

    var body: some View {
        fallbackContent
            .sheet(item: $recoverySheet, content: recoverySheetContent)
    }

    @ViewBuilder
    private var fallbackContent: some View {
        switch presentation {
        case .none:
            EmptyView()
        case .resolving:
            Text("Resolving AI status...")
                .accessibilityIdentifier("S3-10-C3-08-resolving-fallback-status")
        case let .status(status):
            statusContent(status)
        case let .coreStatusError(error):
            HStack(spacing: 10) {
                Text("AI fallback status could not be loaded: \(error.userMessage)")
                let status = SemanticSearchFallbackStatus.fromSemanticPage(page)
                fallbackActionButton(status.presentation(for: .useNormalSearch), status: status)
            }
            .accessibilityIdentifier("S3-10-C3-08-fallback-status-error")
        }
    }

    private var presentation: SemanticSearchFallbackPresentation {
        if case .loading = state { return .resolving }
        if let status = state.status, status.operation == .semanticSearch { return .status(.fromCoreStatus(status)) }
        if let error = state.errorMapping {
            return .coreStatusError(error)
        }
        guard page.fallbackReason != nil else { return .none }
        return .status(.fromSemanticPage(page))
    }

    private func statusContent(_ status: SemanticSearchFallbackStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(status.badge)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(status.badgeTint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("S3-10-C3-08-reason-badge")
                Text(status.title)
                    .fontWeight(.semibold)
            }
            Text(status.message)
            actionRow(status)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S3-10-C3-08-fallback-status")
    }

    private func actionRow(_ status: SemanticSearchFallbackStatus) -> some View {
        HStack(spacing: 10) {
            if status.retryable {
                fallbackActionButton(status.presentation(for: .retry), status: status)
            } else if let retryDisabledReason = status.retryDisabledReason {
                Text(retryDisabledReason)
                    .font(.caption)
            }
            ForEach(status.actionPresentations) { action in
                fallbackActionButton(action, status: status)
            }
        }
    }

    @ViewBuilder
    private func fallbackActionButton(
        _ presentation: SemanticSearchFallbackActionPresentation,
        status: SemanticSearchFallbackStatus
    ) -> some View {
        if status.isVisible(presentation.action) {
            Button(presentation.title) {
                performAction(presentation.action)
            }
            .disabled(isDisabled(presentation.action, status: status))
            .accessibilityIdentifier("S3-10-C3-08-action-\(presentation.accessibilityID)")
        }
    }

    private func performAction(_ action: AiFallbackAction) {
        switch action {
        case .openLocalModelStatus where hasRepoPath:
            recoverySheet = .localModelStatus
        case .configureRemoteAi where hasRepoPath:
            recoverySheet = .remoteConfig
        default:
            onAction(action)
        }
    }

    private var hasRepoPath: Bool {
        repoPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @ViewBuilder
    private func recoverySheetContent(_ sheet: SemanticSearchFallbackRecoverySheet) -> some View {
        if let repoPath = repoPath?.trimmingCharacters(in: .whitespacesAndNewlines), !repoPath.isEmpty {
            switch sheet {
            case .localModelStatus:
                LocalModelStatusView(model: LocalModelStatusModel(repoPath: repoPath)) {
                    recoverySheet = nil
                }
            case .remoteConfig:
                RemoteModelConfigSheet(model: RemoteProviderConfigModel(repoPath: repoPath)) {
                    recoverySheet = nil
                }
            }
        }
    }

    private func isDisabled(_ action: AiFallbackAction, status: SemanticSearchFallbackStatus) -> Bool {
        switch action {
        case .retry:
            !status.retryable
        case .retryLater:
            true
        case .viewPrivacyRule:
            status.privacyRuleID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        case .viewCallLog:
            status.callLogID == nil
        case .buildSemanticIndex:
            isIndexBuildBusy || isPrivacyGateChecking || !status.canBuildSemanticIndex
        case .openAiSettings, .openLocalModelStatus, .configureRemoteAi, .useNormalSearch:
            false
        case .classifyManually:
            true
        }
    }
}

private enum SemanticSearchFallbackPresentation {
    case none
    case resolving
    case status(SemanticSearchFallbackStatus)
    case coreStatusError(CoreErrorMappingSnapshot)
}

private enum SemanticSearchFallbackRecoverySheet: String, Identifiable {
    case localModelStatus, remoteConfig

    var id: String {
        rawValue
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
