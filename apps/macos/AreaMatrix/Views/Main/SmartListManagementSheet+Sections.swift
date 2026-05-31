import SwiftUI

extension MainRepositoryContentView {
    var searchLoadingText: String {
        searchMode == .semantic ? "Searching semantically..." : "Searching..."
    }

    @ViewBuilder
    var semanticIndexBuildText: some View {
        switch fileListModel.semanticIndexBuildState {
        case .idle:
            EmptyView()
        case .building:
            Text("Building semantic index...")
        case let .completed(_, report):
            Text("Semantic index \(report.status.displayName.lowercased()): \(report.processedCount)/\(report.totalCount) processed")
        case let .failed(_, error):
            Text("Semantic index could not be built: \(error.userMessage)")
        }
    }

    var semanticPrivacyGateText: String {
        switch fileListModel.semanticPrivacyGateState {
        case .idle:
            "Privacy rules: not checked yet"
        case .checking:
            "Privacy rules: checking..."
        case let .allowed(_, report):
            "Privacy rules: allowed. Sent fields: \(privacySentFields(report.sentFields))"
        case let .blocked(_, report):
            "Privacy rules: blocked. \(report.message) Sent fields: \(privacySentFields(report.sentFields))"
        case let .failed(_, error):
            "Privacy rules could not be checked: \(error.userMessage)"
        }
    }

    var semanticIndexConfirmationMessage: String {
        [
            "AreaMatrix will build a semantic index for searchable files.",
            "Local indexing keeps file content on this device.",
            "Remote indexing is used only when remote AI is explicitly enabled and allowed for Semantic search.",
            semanticPrivacyGateText
        ].joined(separator: " ")
    }

    func semanticPrivacyRuleSheet(_ route: AIClassificationPrivacyRuleRoute) -> some View {
        AIClassificationPrivacyRuleReferenceSheet(repoPath: opening.config.repoPath, ruleID: route.ruleID) {
            semanticPrivacyRuleRoute = nil
        }
    }

    func semanticCallLogSheet(_ route: SemanticSearchCallLogRoute) -> some View {
        AIClassificationCallLogDetailSheet(
            repoPath: opening.config.repoPath,
            callLogID: route.callLogID,
            feature: .semanticSearch
        ) {
            semanticCallLogRoute = nil
        }
    }

    @ViewBuilder
    var semanticIndexRecoveryActions: some View {
        if let ruleID = fileListModel.semanticPrivacyGateState.matchedRuleID {
            Button("View privacy rule") {
                semanticPrivacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
            }
            .accessibilityIdentifier("S3-08-C3-09-view-privacy-rule")
        }
        switch fileListModel.semanticPrivacyGateState {
        case .blocked, .failed:
            Button("Retry privacy check") {
                Task { await fileListModel.refreshSemanticPrivacyGateForCurrentSearch() }
            }
            Button("Use normal search") {
                isSemanticIndexConfirmationPresented = false
                searchMode = .normal
                Task { await rerunCurrentSearch(mode: .normal) }
            }
        case .idle, .checking, .allowed:
            EmptyView()
        }
    }

    func semanticStatusText(_ page: SemanticSearchResultPageSnapshot) -> String {
        var parts = ["Semantic index: \(page.indexStatus.displayName)"]
        if let route = page.route { parts.append(route.rawValue) }
        if page.lowConfidence { parts.append("Low confidence results") }
        if let fallback = page.fallbackReason { parts.append(page.fallbackMessage ?? fallback.rawValue) }
        if page.dedupedNormalCount > 0 { parts.append("\(page.dedupedNormalCount) duplicate normal matches folded") }
        return parts.joined(separator: "  ")
    }

    func semanticMatchText(_ presentation: SemanticResultPresentation) -> String {
        switch presentation {
        case let .semantic(match):
            let fields = match.usedFields.map(\.rawValue).joined(separator: ", ")
            let duplicate = match.alsoMatchedNormalSearch ? " | Also matched normal search" : ""
            return "Semantic | \(String(format: "%.2f", match.relevance)) | \(match.matchedReason) | \(fields)\(duplicate)"
        case let .normal(match):
            if let noteSnippet = match.result.noteSnippet, !noteSnippet.isEmpty {
                return "Normal | - | Note: \(noteSnippet)"
            }
            guard let first = match.result.matches.first else { return "Normal | - | Match" }
            return "Normal | - | \(first.kindDisplayName): \(first.fieldDisplayName) - \(first.snippet)"
        }
    }

    @ViewBuilder
    func semanticBannerDetail(_ page: SemanticSearchResultPageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(semanticStatusText(page))
                Button("Use normal search") {
                    searchMode = .normal
                    Task { await rerunCurrentSearch(mode: .normal) }
                }
                semanticBuildIndexButton(page)
            }
            Text("Semantic matches (\(page.semanticTotalCount))  Normal search matches (\(page.normalTotalCount))")
            semanticIndexBuildText
            semanticPrivacyGateDetail
            semanticFallbackStatusDetail
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("S3-08-C3-10-ai-fallback")
    }

    @ViewBuilder
    private var semanticFallbackStatusDetail: some View {
        switch fileListModel.semanticFallbackState {
        case .idle:
            EmptyView()
        case .loading:
            Text("Resolving AI status...")
                .accessibilityIdentifier("S3-08-C3-10-resolving-fallback-status")
        case let .loaded(_, status):
            VStack(alignment: .leading, spacing: 6) {
                Text(status.title)
                    .fontWeight(.semibold)
                Text(status.message)
                HStack(spacing: 10) {
                    if status.retryable {
                        semanticFallbackActionButton(.retry, status: status)
                    } else if let retryDisabledReason = status.retryDisabledReason {
                        Text(retryDisabledReason)
                            .font(.caption)
                    }
                    ForEach(semanticFallbackActions(for: status), id: \.self) { action in
                        semanticFallbackActionButton(action, status: status)
                    }
                }
            }
            .accessibilityIdentifier("S3-08-C3-10-fallback-status")
        case let .failed(_, error):
            HStack(spacing: 10) {
                Text("AI fallback status could not be loaded: \(error.userMessage)")
                Button("Use normal search") {
                    searchMode = .normal
                    Task { await rerunCurrentSearch(mode: .normal) }
                }
            }
            .accessibilityIdentifier("S3-08-C3-10-fallback-status-error")
        }
    }

    private func semanticFallbackActions(for status: AiFallbackStatus) -> [AiFallbackAction] {
        [
            status.primaryAction == .retry ? nil : status.primaryAction,
            status.secondaryAction,
            status.nonAiFallbackAction
        ].compactMap { $0 }.reduce(into: []) { actions, action in
            if semanticFallbackActionIsVisible(action), !actions.contains(action) {
                actions.append(action)
            }
        }
    }

    @ViewBuilder
    private func semanticFallbackActionButton(_ action: AiFallbackAction, status: AiFallbackStatus) -> some View {
        if semanticFallbackActionIsVisible(action) {
            Button(semanticFallbackActionTitle(action)) {
                performSemanticFallbackAction(action, status: status)
            }
            .disabled(semanticFallbackActionIsDisabled(action, status: status))
            .accessibilityIdentifier("S3-08-C3-10-action-\(semanticFallbackActionID(action))")
        }
    }

    private func semanticFallbackActionIsVisible(_ action: AiFallbackAction) -> Bool {
        switch action {
        case .retry, .retryLater, .openAiSettings, .configureRemoteAi, .viewPrivacyRule, .viewCallLog,
             .buildSemanticIndex, .useNormalSearch:
            true
        case .openLocalModelStatus, .classifyManually:
            false
        }
    }

    private func semanticFallbackActionIsDisabled(_ action: AiFallbackAction, status: AiFallbackStatus) -> Bool {
        switch action {
        case .retry:
            !status.retryable
        case .retryLater:
            true
        case .viewPrivacyRule:
            status.privacyRuleId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        case .viewCallLog:
            status.callLogId == nil
        case .buildSemanticIndex:
            fileListModel.semanticIndexBuildState.isBuilding || fileListModel.semanticPrivacyGateState.isChecking
        case .openAiSettings, .configureRemoteAi, .useNormalSearch:
            false
        case .openLocalModelStatus, .classifyManually:
            true
        }
    }

    private func performSemanticFallbackAction(_ action: AiFallbackAction, status: AiFallbackStatus) {
        switch action {
        case .retry:
            Task { await fileListModel.retrySearch() }
        case .openAiSettings, .configureRemoteAi:
            onOpenAISettings()
        case .viewPrivacyRule:
            if let ruleID = status.privacyRuleId?.trimmingCharacters(in: .whitespacesAndNewlines), !ruleID.isEmpty {
                semanticPrivacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
            }
        case .viewCallLog:
            if let callLogID = status.callLogId {
                semanticCallLogRoute = SemanticSearchCallLogRoute(callLogID: callLogID)
            }
        case .buildSemanticIndex:
            Task {
                await fileListModel.refreshSemanticPrivacyGateForCurrentSearch()
                isSemanticIndexConfirmationPresented = true
            }
        case .useNormalSearch:
            searchMode = .normal
            Task { await rerunCurrentSearch(mode: .normal) }
        case .retryLater, .openLocalModelStatus, .classifyManually:
            break
        }
    }

    private func semanticFallbackActionTitle(_ action: AiFallbackAction) -> String {
        switch action {
        case .retry: "Retry"
        case .retryLater: "Retry later"
        case .openAiSettings: "Open AI settings"
        case .openLocalModelStatus: "Open local model status"
        case .configureRemoteAi: "Configure remote AI"
        case .viewPrivacyRule: "View privacy rule"
        case .viewCallLog: "View call log"
        case .buildSemanticIndex: "Build semantic index"
        case .useNormalSearch: "Use normal search"
        case .classifyManually: "Classify manually"
        }
    }

    private func semanticFallbackActionID(_ action: AiFallbackAction) -> String {
        switch action {
        case .retry: "retry"
        case .retryLater: "retry-later"
        case .openAiSettings: "open-ai-settings"
        case .openLocalModelStatus: "open-local-model-status"
        case .configureRemoteAi: "configure-remote-ai"
        case .viewPrivacyRule: "view-privacy-rule"
        case .viewCallLog: "view-call-log"
        case .buildSemanticIndex: "build-semantic-index"
        case .useNormalSearch: "use-normal-search"
        case .classifyManually: "classify-manually"
        }
    }

    @ViewBuilder
    private var semanticPrivacyGateDetail: some View {
        switch fileListModel.semanticPrivacyGateState {
        case .idle:
            EmptyView()
        case .checking:
            Text("Checking privacy rules before semantic indexing...")
        case let .allowed(_, report):
            Text("Privacy gate allowed semantic indexing. Sent fields: \(privacySentFields(report.sentFields))")
        case let .blocked(_, report):
            HStack(spacing: 10) {
                Text("Privacy gate blocked semantic indexing. \(report.message)")
                if let ruleID = fileListModel.semanticPrivacyGateState.matchedRuleID {
                    Button("View privacy rule") {
                        semanticPrivacyRuleRoute = AIClassificationPrivacyRuleRoute(ruleID: ruleID)
                    }
                }
                Button("Retry privacy check") {
                    Task { await fileListModel.refreshSemanticPrivacyGateForCurrentSearch() }
                }
            }
        case let .failed(_, error):
            HStack(spacing: 10) {
                Text("Privacy gate check failed: \(error.userMessage)")
                Button("Retry privacy check") {
                    Task { await fileListModel.refreshSemanticPrivacyGateForCurrentSearch() }
                }
            }
        }
    }

    @ViewBuilder
    private func semanticBuildIndexButton(_ page: SemanticSearchResultPageSnapshot) -> some View {
        if page.canBuildIndex {
            Button("Build semantic index") {
                Task {
                    await fileListModel.refreshSemanticPrivacyGateForCurrentSearch()
                    isSemanticIndexConfirmationPresented = true
                }
            }
            .disabled(fileListModel.semanticIndexBuildState.isBuilding || fileListModel.semanticPrivacyGateState.isChecking)
            .accessibilityIdentifier("S3-08-C3-09-build-semantic-index-privacy-check")
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
    var id: Int64 { callLogID }
}

extension SmartListManagementSheet {
    @ViewBuilder
    var content: some View {
        failureView
        switch model.mode {
        case .delete:
            deleteContent
        case .rename:
            nameEditor
            footer
        case .duplicate:
            nameEditor
            Toggle("Pin to sidebar", isOn: $model.pinned)
                .disabled(model.isSaving)
            preview
            footer
        case .editQuery:
            savedSummary
            queryEditor
            preview
            footer
        }
    }

    @ViewBuilder
    var failureView: some View {
        if let validationMessage = model.validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("S2-06-validation-error")
        }
        if let failure = model.failure {
            HStack(spacing: 8) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                Spacer()
                if model.showsRetry {
                    Button("Retry") { Task { await submit() } }
                        .accessibilityIdentifier("S2-06-save-retry")
                }
            }
            .foregroundStyle(.red)
            .accessibilityIdentifier("S2-06-save-error")
        }
        if let diagnostic = model.queryDiagnostic {
            QueryDiagnosticSummary(diagnostic: diagnostic, query: model.queryDiagnosticRequest.query)
        }
    }

    var nameEditor: some View {
        TextField("Name", text: $model.name)
            .textFieldStyle(.roundedBorder)
            .disabled(model.isSaving)
            .accessibilityIdentifier("S2-06-smart-list-name")
    }

    var savedSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            metadataRow("Name", model.original.name)
            metadataRow("Icon", model.original.icon ?? "Default")
            metadataRow("Pin", pinSummary)
        }
    }

    var queryEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Query", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isSaving)
            Picker("Scope", selection: $model.scope) {
                ForEach(SearchScopeSnapshot.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            Picker("Sort", selection: $model.sort) {
                ForEach(SearchSortSnapshot.allCases) { sort in
                    Text(sort.displayName).tag(sort)
                }
            }
        }
        .accessibilityIdentifier("S2-06-edit-query-fields")
    }

    var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow("Filters", model.filterSummary)
            metadataRow("Current results", model.resultCountSummary)
        }
        .accessibilityIdentifier("S2-06-smart-list-preview")
    }

    var deleteContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete \"\(model.original.name)\"?")
                .font(.callout.weight(.semibold))
            Text(SmartListEditorModel.deleteSafetyMessage)
                .font(.callout).foregroundStyle(.secondary)
            footer
        }
    }

    var footer: some View {
        HStack {
            if model.mode == .editQuery {
                Button("Reset changes", action: resetChanges)
                    .disabled(model.isSaving)
                Button("Edit filters") { onEditFilters(model.original, model.filters) }
                    .disabled(model.isSaving)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(model.isSaving)
            Button(model.primaryActionTitle, role: model.mode == .delete ? .destructive : nil) {
                Task { await submit() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("S2-06-primary-action")
        }
    }

    var pinSummary: String {
        model.original.pinned ? "Pinned" : "Not pinned"
    }

    func resetChanges() {
        model.query = model.original.query.query
        model.scope = model.original.query.scope
        model.filters = model.original.query.filter
        model.sort = model.original.query.sort
        model.failure = nil
        model.clearQueryDiagnostic()
    }
}
