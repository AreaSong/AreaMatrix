import SwiftUI

extension MainRepositoryContentView {
    var searchLoadingText: String {
        searchMode == .semantic ? L10n.string("Searching semantically...") : L10n.string("Searching...")
    }

    @ViewBuilder
    var semanticIndexBuildText: some View {
        switch fileListModel.semanticIndexBuildState {
        case .idle:
            EmptyView()
        case let .building(request):
            Text(L10n.format("search.semanticIndex.building", semanticBuildProgressText(for: request)))
        case let .completed(_, report):
            Text(semanticCompletedIndexText(report))
        case .canceled:
            Text(L10n.string("Semantic index build canceled."))
        case let .failed(_, error):
            Text(L10n.format("search.semanticIndex.buildFailed", error.userMessage))
        }
    }

    private func semanticBuildProgressText(for request: SearchQueryRequestSnapshot) -> String {
        guard let page = fileListModel.searchState.page?.semanticPage else { return "" }
        let processed = max(0, page.semanticTotalCount - page.dedupedNormalCount)
        let total = max(page.semanticTotalCount + page.normalTotalCount, Int64(1))
        let percent = min(100, Int((Double(processed) / Double(total)) * 100))
        return L10n.format("search.semanticIndex.progress", percent, processed, total, request.query)
    }

    private func semanticCompletedIndexText(_ report: SemanticIndexBuildReportSnapshot) -> String {
        switch report.status {
        case .canceled:
            L10n.string("Semantic index build canceled.")
        case .paused:
            L10n.string("Semantic index build paused.")
        case .partial:
            L10n.format(
                "search.semanticIndex.partial",
                report.processedCount,
                report.totalCount,
                report.failedCount
            )
        case .failed:
            L10n.string("Semantic index could not be built.")
        case .ready:
            L10n.format("search.semanticIndex.ready", report.processedCount, report.totalCount)
        case .notReady, .building:
            L10n.format(
                "search.semanticIndex.status",
                report.status.displayName.lowercased(),
                report.processedCount,
                report.totalCount
            )
        }
    }

    var semanticPrivacyGateText: String {
        switch fileListModel.semanticPrivacyGateState {
        case .idle:
            L10n.string("Privacy rules: not checked yet")
        case .checking:
            L10n.string("Privacy rules: checking...")
        case let .allowed(_, report):
            L10n.format("search.semanticIndex.privacyAllowed", privacySentFields(report.sentFields))
        case let .blocked(_, report):
            L10n.format(
                "search.semanticIndex.privacyBlocked",
                report.message,
                privacySentFields(report.sentFields)
            )
        case let .failed(_, error):
            L10n.format("search.semanticIndex.privacyCheckFailed", error.userMessage)
        }
    }

    var semanticIndexConfirmationMessage: String {
        [
            L10n.string("AreaMatrix will build a semantic index for searchable files."),
            L10n.string("Local indexing keeps file content on this device."),
            L10n.string(
                "Remote indexing is used only when remote AI is explicitly enabled and allowed for Semantic search."
            ),
            semanticPrivacyGateText
        ].joined(separator: " ")
    }

    var semanticIndexCancelConfirmationMessage: String {
        [
            L10n.string("AreaMatrix will stop processing remaining files."),
            L10n.string("Already committed local index fragments can still be used."),
            L10n.string("Uncommitted index writes will be cleaned up."),
            L10n.string("Remote queues will stop and no more content will be sent.")
        ].joined(separator: " ")
    }

    func semanticPrivacyRuleSheet(_ route: AIClassificationPrivacyRuleRoute) -> some View {
        AIClassificationPrivacyRuleReferenceSheet(repoPath: opening.config.repoPath, ruleID: route.ruleID) {
            searchRoutingState.semanticPrivacyRuleRoute = nil
        }
    }

    func semanticCallLogSheet(_ route: SemanticSearchCallLogRoute) -> some View {
        AIClassificationCallLogDetailSheet(
            repoPath: opening.config.repoPath,
            callLogID: route.callLogID,
            feature: .semanticSearch
        ) {
            searchRoutingState.semanticCallLogRoute = nil
        }
    }

    @ViewBuilder
    var semanticIndexRecoveryActions: some View {
        if let ruleID = fileListModel.semanticPrivacyGateState.matchedRuleID {
            Button(L10n.string("View privacy rule")) {
                searchRoutingState.semanticPrivacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
            }
            .accessibilityIdentifier("semantic-search-ai-privacy-rules-core-view-privacy-rule")
        }
        switch fileListModel.semanticPrivacyGateState {
        case .blocked, .failed:
            Button(L10n.string("Retry privacy check")) {
                Task { await fileListModel.refreshSemanticPrivacyGateForCurrentSearch() }
            }
            Button(L10n.string("Use normal search")) {
                searchRoutingState.isSemanticIndexConfirmationPresented = false
                searchMode = .normal
                Task { await rerunCurrentSearch(mode: .normal) }
            }
            semanticCallLogRecoveryButton
        case .idle, .checking, .allowed:
            semanticCallLogRecoveryButton
        }
    }

    @ViewBuilder
    private var semanticCallLogRecoveryButton: some View {
        if let callLogID = fileListModel.searchState.page?.semanticPage?.callLogID {
            Button(L10n.string("View call log")) {
                searchRoutingState.semanticCallLogRoute = SemanticSearchCallLogRoute(callLogID: callLogID)
            }
        }
    }

    func semanticStatusText(_ page: SemanticSearchResultPageSnapshot) -> String {
        var parts = [L10n.format("semanticSearch.indexStatus", page.indexStatus.displayName)]
        if let route = page.route { parts.append(route.displayName) }
        if page.lowConfidence { parts.append(L10n.string("Low confidence results")) }
        if let fallback = page.fallbackReason { parts.append(page.fallbackMessage ?? fallback.displayName) }
        if page.dedupedNormalCount > 0 {
            parts.append(L10n.format("semanticSearch.foldedNormalCount", page.dedupedNormalCount))
        }
        return parts.joined(separator: "  ")
    }

    func semanticMatchText(_ presentation: SemanticResultPresentation) -> String {
        switch presentation {
        case let .semantic(match):
            let fields = match.usedFields.map(\.displayName).joined(separator: ", ")
            let duplicate = match.alsoMatchedNormalSearch ? L10n.string(" | Also matched normal search") : ""
            return L10n.format(
                "semanticSearch.semanticMatchDiagnostic",
                String(format: "%.2f", match.relevance),
                match.matchedReason,
                fields,
                duplicate
            )
        case let .normal(match):
            if let noteSnippet = match.result.noteSnippet, !noteSnippet.isEmpty {
                return L10n.format("semanticSearch.normalNoteDiagnostic", noteSnippet)
            }
            guard let first = match.result.matches.first else {
                return L10n.string("Normal | - | Match")
            }
            return L10n.format(
                "semanticSearch.normalMatchDiagnostic",
                first.kindDisplayName,
                first.fieldDisplayName,
                first.snippet
            )
        }
    }

    func semanticBannerDetail(_ page: SemanticSearchResultPageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(semanticStatusText(page))
                Button(L10n.string("Use normal search")) {
                    searchMode = .normal
                    Task { await rerunCurrentSearch(mode: .normal) }
                }
                semanticBuildIndexButton(page)
                semanticBuildLifecycleControls
            }
            Text(L10n.plural("search.semanticMatchCount", count: page.semanticTotalCount))
            Text(L10n.plural("search.normalMatchCount", count: page.normalTotalCount))
            semanticIndexBuildText
            semanticCancelStatusText
            semanticPrivacyGateDetail
            SemanticSearchFallbackStatusRegion(
                page: page,
                state: fileListModel.semanticFallbackState,
                repoPath: opening.config.repoPath,
                isIndexBuildBusy: fileListModel.semanticIndexBuildState.isBuilding ||
                    fileListModel.semanticIndexControlState.isCanceling,
                isPrivacyGateChecking: fileListModel.semanticPrivacyGateState.isChecking,
                onAction: performSemanticFallbackAction(_:)
            )
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("ai-fallback-semantic-search-core-ai-fallback")
    }

    private func performSemanticFallbackAction(_ action: AiFallbackAction) {
        switch action {
        case .retry:
            Task { await fileListModel.retrySearch() }
        case .openAiSettings:
            onOpenAISettings()
        case .openLocalModelStatus, .configureRemoteAi:
            break
        case .viewPrivacyRule:
            let ruleID = fileListModel.semanticFallbackState.status?.privacyRuleId ??
                fileListModel.searchState.page?.semanticPage?.privacyRuleID
            if let ruleID = ruleID?.trimmingCharacters(in: .whitespacesAndNewlines), !ruleID.isEmpty {
                searchRoutingState.semanticPrivacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
            }
        case .viewCallLog:
            let callLogID = fileListModel.semanticFallbackState.status?.callLogId ??
                fileListModel.searchState.page?.semanticPage?.callLogID
            if let callLogID {
                searchRoutingState.semanticCallLogRoute = SemanticSearchCallLogRoute(callLogID: callLogID)
            }
        case .buildSemanticIndex:
            Task {
                await fileListModel.refreshSemanticPrivacyGateForCurrentSearch()
                searchRoutingState.isSemanticIndexConfirmationPresented = true
            }
        case .useNormalSearch:
            searchMode = .normal
            Task { await rerunCurrentSearch(mode: .normal) }
        case .retryLater, .classifyManually:
            break
        }
    }

    @ViewBuilder
    private var semanticPrivacyGateDetail: some View {
        switch fileListModel.semanticPrivacyGateState {
        case .idle:
            EmptyView()
        case .checking:
            Text(L10n.string("Checking privacy rules before semantic indexing..."))
        case let .allowed(_, report):
            Text(L10n.format(
                "search.semanticIndex.privacyGateAllowed",
                privacySentFields(report.sentFields)
            ))
        case let .blocked(_, report):
            HStack(spacing: 10) {
                Text(L10n.format("search.semanticIndex.privacyGateBlocked", report.message))
                if let ruleID = fileListModel.semanticPrivacyGateState.matchedRuleID {
                    Button(L10n.string("View privacy rule")) {
                        searchRoutingState.semanticPrivacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
                    }
                }
                Button(L10n.string("Retry privacy check")) {
                    Task { await fileListModel.refreshSemanticPrivacyGateForCurrentSearch() }
                }
            }
        case let .failed(_, error):
            HStack(spacing: 10) {
                Text(L10n.format("search.semanticIndex.privacyGateCheckFailed", error.userMessage))
                Button(L10n.string("Retry privacy check")) {
                    Task { await fileListModel.refreshSemanticPrivacyGateForCurrentSearch() }
                }
            }
        }
    }

    @ViewBuilder
    private var semanticBuildLifecycleControls: some View {
        if fileListModel.semanticIndexBuildState.canPause {
            Button(L10n.string("Pause index build")) {
                Task { await fileListModel.pauseSemanticIndexBuildForCurrentSearch() }
            }
            .disabled(fileListModel.semanticIndexControlState.isCanceling)
            .accessibilityIdentifier("semantic-search-pause-index-build")
        }
        if fileListModel.semanticIndexBuildState.canCancel {
            Button(L10n.string("Cancel index build")) {
                fileListModel.requestCancelSemanticIndexBuildForCurrentSearch()
            }
            .disabled(fileListModel.semanticIndexControlState.isCanceling)
            .accessibilityIdentifier("semantic-search-cancel-index-build")
        }
        if fileListModel.semanticIndexBuildState.canResume {
            Button(L10n.string("Resume index build")) {
                Task { await fileListModel.resumeSemanticIndexBuildForCurrentSearch() }
            }
            .accessibilityIdentifier("semantic-search-resume-index-build")
        }
        if fileListModel.semanticIndexBuildState.canRetryFailedItems {
            Button(L10n.string("Retry failed items")) {
                Task { await fileListModel.retryFailedSemanticIndexItemsForCurrentSearch() }
            }
            .disabled(fileListModel.semanticIndexControlState.isCanceling)
            .accessibilityIdentifier("semantic-search-retry-failed-items")
        }
    }

    @ViewBuilder
    private var semanticCancelStatusText: some View {
        switch fileListModel.semanticIndexControlState {
        case .canceling:
            Text(L10n.string("Canceling semantic index build..."))
        case .canceled:
            Text(L10n.string("Semantic index build canceled."))
            HStack(spacing: 10) {
                Button(L10n.string("Retry index build")) {
                    Task { await fileListModel.retryFailedSemanticIndexItemsForCurrentSearch() }
                }
                Button(L10n.string("View call log")) {
                    if let callLogID = fileListModel.searchState.page?.semanticPage?.callLogID {
                        searchRoutingState.semanticCallLogRoute = SemanticSearchCallLogRoute(callLogID: callLogID)
                    }
                }
            }
        case let .cancelFailed(_, error):
            HStack(spacing: 10) {
                Text(L10n.format("search.semanticIndex.cancelFailed", error.userMessage))
                Button(L10n.string("Retry cancel")) {
                    Task { await fileListModel.cancelSemanticIndexBuildForCurrentSearch() }
                }
                Button(L10n.string("View call log")) {
                    if let callLogID = fileListModel.searchState.page?.semanticPage?.callLogID {
                        searchRoutingState.semanticCallLogRoute = SemanticSearchCallLogRoute(callLogID: callLogID)
                    }
                }
            }
        case let .pauseFailed(_, error):
            HStack(spacing: 10) {
                Text(L10n.format("search.semanticIndex.pauseFailed", error.userMessage))
                Button(L10n.string("Use normal search")) {
                    searchMode = .normal
                    Task { await rerunCurrentSearch(mode: .normal) }
                }
            }
        case .idle, .cancelConfirm:
            EmptyView()
        }
    }

    @ViewBuilder
    private func semanticBuildIndexButton(_ page: SemanticSearchResultPageSnapshot) -> some View {
        if page.canBuildIndex {
            Button(L10n.string("Build semantic index")) {
                Task {
                    await fileListModel.refreshSemanticPrivacyGateForCurrentSearch()
                    searchRoutingState.isSemanticIndexConfirmationPresented = true
                }
            }
            .disabled(
                fileListModel.semanticIndexBuildState.isBuilding ||
                    fileListModel.semanticIndexControlState.isCanceling ||
                    fileListModel.semanticPrivacyGateState.isChecking
            )
            .accessibilityIdentifier("semantic-search-ai-privacy-rules-core-build-semantic-index-privacy-check")
        }
    }

    func rerunCurrentSearch(mode: SearchModeSnapshot) async {
        await fileListModel.runSearch(
            query: filterText,
            scope: searchScope,
            sort: searchSort,
            sidebarRow: selectedSidebarRow,
            filters: effectiveSearchFilters,
            mode: mode
        )
    }
}

struct SemanticSearchCallLogRoute: Identifiable, Equatable {
    var callLogID: Int64
    var id: Int64 {
        callLogID
    }
}
