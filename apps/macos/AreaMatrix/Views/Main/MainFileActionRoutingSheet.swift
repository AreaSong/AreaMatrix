import SwiftUI

struct MainFileActionRoutingSheet: View {
    let destination: MainFileActionDestination
    let file: FileEntrySnapshot?
    let candidateFiles: [FileEntrySnapshot]
    let categoryRows: [RepositorySidebarRowSnapshot]
    let renameState: MainFileRenameState
    let deleteState: MainFileDeleteState
    let changeCategoryState: MainFileCategoryMoveState
    let classifierCorrectionContextState: ClassifierCorrectionContextState
    let iCloudConflictResolutionState: ICloudConflictResolutionState
    let iCloudConflictResolutionCapability: ICloudConflictResolutionCapability
    let repoPath: String
    let isTrashAvailable: Bool
    let iCloudConflictPathValidator: any CoreRepositoryPathValidating
    let iCloudConflictErrorMapper: any CoreErrorMapping
    let onDismiss: () -> Void
    let onRename: (Int64, String) -> Void
    let onShowExistingFile: (Int64) -> Void
    let onPreviewChangeCategory: (Int64, String) -> Void
    let onLoadClassifierCorrectionContext: (Int64, String) -> Void
    let onChangeCategory: (Int64, String, MainFileCategoryMoveMode, MainFileCategoryMoveOptions) -> Void
    let onBeginClassifierRuleHandoff: (Int64, String, Bool, ClassifierRuleHandoffDestination) -> Void
    let onRenameFirstFromChangeCategory: (Int64, String) -> Void
    let onEditClassifierRule: (ClassifierRuleHandoff) -> Void
    let onPreviewClassifierRuleImpact: (ClassifierRuleHandoff) -> Void
    let onOpenChangeCategoryPermissionRecovery: () -> Void
    let onDelete: (Int64, MainFileDeleteOperation) -> Void
    let onApplyICloudConflict: (
        Int64,
        ICloudConflictResolutionStrategy,
        String?,
        String?
    ) -> Void
    let onCollectDiagnostics: () -> Void

    var body: some View {
        switch destination {
        case .rename:
            RenameFileSheet(
                file: file,
                candidateFiles: candidateFiles,
                state: renameState,
                onCancel: onDismiss,
                onRename: onRename,
                onShowExistingFile: onShowExistingFile
            )
        case .changeCategory:
            changeCategoryRouteView(destination)
        case .delete:
            DeleteFileConfirmSheet(
                file: file,
                operation: file.map(MainFileDeleteOperation.recommended),
                state: deleteState,
                isTrashAvailable: isTrashAvailable,
                onCancel: onDismiss,
                onConfirm: onDelete,
                onCollectDiagnostics: onCollectDiagnostics
            )
        case let .iCloudConflict(fileID):
            ICloudConflictMinimalSheet(
                model: ICloudConflictMinimalModel(
                    repoPath: repoPath,
                    originalVersion: ICloudConflictVersionSnapshot.originalCandidate(repoPath: repoPath, file: file),
                    conflictedCopyVersion: ICloudConflictVersionSnapshot.conflictedCandidate(
                        repoPath: repoPath,
                        file: file
                    ),
                    pathValidator: iCloudConflictPathValidator,
                    errorMapper: iCloudConflictErrorMapper
                ),
                resolutionState: iCloudConflictResolutionState,
                resolutionCapability: iCloudConflictResolutionCapability,
                isTrashAvailable: isTrashAvailable,
                onCancel: onDismiss,
                onApply: { strategy, originalPath, conflictedCopyPath in
                    onApplyICloudConflict(fileID, strategy, originalPath, conflictedCopyPath)
                },
                onCollectDiagnostics: {
                    onCollectDiagnostics()
                }
            )
        }
    }

    @ViewBuilder
    private func changeCategoryRouteView(_ destination: MainFileActionDestination) -> some View {
        if let ruleRoute = destination.classifierRuleRoute {
            classifierRuleRouteView(ruleRoute)
        } else {
            ChangeCategorySheet(
                file: file,
                categoryRows: categoryRows,
                state: changeCategoryState,
                classifierContextState: classifierCorrectionContextState,
                mode: destination.changeCategoryMode,
                initialTargetCategory: destination.initialChangeCategoryTarget,
                onCancel: onDismiss,
                onPreview: onPreviewChangeCategory,
                onLoadClassifierContext: onLoadClassifierCorrectionContext,
                onChangeCategory: onChangeCategory,
                onBeginRuleHandoff: onBeginClassifierRuleHandoff,
                onRenameFirst: onRenameFirstFromChangeCategory,
                onOpenPermissionRecovery: onOpenChangeCategoryPermissionRecovery,
                onCollectDiagnostics: onCollectDiagnostics
            )
        }
    }

    private func classifierRuleRouteView(_ route: ClassifierCorrectionRuleRoute) -> some View {
        ClassifierRuleHandoffRouteView(
            mode: route.handoffMode,
            handoff: route.handoff,
            onCancel: onDismiss,
            onBack: onEditClassifierRule,
            onPreviewImpact: onPreviewClassifierRuleImpact
        )
    }
}
struct SavedSearchPreview: View {
    let model: SavedSearchSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataRow("Query", model.querySummary)
            metadataRow("Filters", model.filterSummary)
            metadataRow("Sort", model.request.sort.displayName)
            metadataRow("Current results", model.resultCountSummary)
            if let warning = model.emptyResultWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S2-03-saved-search-preview")
    }
}

struct SavedSearchSheetRouteView: View {
    let request: SearchQueryRequestSnapshot
    let repoPath: String
    let resultCountState: SavedSearchResultCountState
    let savedSearchStore: any CoreSavedSearchCRUD
    let errorMapper: any CoreErrorMapping
    let onCancel: () -> Void
    let onSaved: (SavedSearchSnapshot) -> Void
    let onEditFilters: () -> Void
    @State private var model: SavedSearchSheetModel
    @State private var showSavingCancelPrompt = false

    init(
        request: SearchQueryRequestSnapshot,
        repoPath: String = "",
        resultCountState: SavedSearchResultCountState = .loading,
        savedSearchStore: any CoreSavedSearchCRUD = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onCancel: @escaping () -> Void,
        onSaved: @escaping (SavedSearchSnapshot) -> Void = { _ in },
        onEditFilters: @escaping () -> Void = {}
    ) {
        self.request = request
        self.repoPath = repoPath
        self.resultCountState = resultCountState
        self.savedSearchStore = savedSearchStore
        self.errorMapper = errorMapper
        self.onCancel = onCancel
        self.onSaved = onSaved
        self.onEditFilters = onEditFilters
        _model = State(initialValue: SavedSearchSheetModel(
            request: request,
            resultCountState: resultCountState
        ))
    }

    var body: some View {
        MainFileActionSheetContainer(title: "Save Search", pageID: "S2-03") {
            Text("Save the current query as a Smart List. Files are not moved or duplicated.")
                .font(.callout)
                .foregroundStyle(.secondary)
            savedSearchErrorView
            TextField("Name", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isSaving)
                .accessibilityIdentifier("S2-03-saved-search-name")
            Picker("Icon", selection: $model.icon) {
                ForEach(SavedSearchSheetModel.icons, id: \.self) { icon in
                    Label(icon, systemImage: icon).tag(icon)
                }
            }
            .disabled(model.isSaving)
            Toggle("Pin to sidebar", isOn: $model.pinned)
                .disabled(model.isSaving)
            SavedSearchPreview(model: model)
            HStack {
                Button("Edit filters", action: onEditFilters)
                    .disabled(model.isSaving)
                Spacer()
                Button("Cancel") {
                    if model.isSaving {
                        showSavingCancelPrompt = true
                    } else {
                        onCancel()
                    }
                }
                    .keyboardShortcut(.cancelAction)
                Button(model.primaryActionTitle) {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canSave)
            }
        }
        .confirmationDialog(
            "Saving is in progress.",
            isPresented: $showSavingCancelPrompt,
            titleVisibility: .visible
        ) {
            Button("Continue Saving", role: .cancel) {}
        }
        .task {
            await loadExistingSavedSearches()
        }
        .accessibilityIdentifier("S2-03-search-route")
    }

    @ViewBuilder
    private var savedSearchErrorView: some View {
        if let validationMessage = model.validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("S2-03-validation-error")
        }
        if let failure = model.saveFailure {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("S2-03-save-error")
                Spacer()
                Button("Retry") {
                    Task { await save() }
                }
                .disabled(!model.showsRetry || model.validationMessage != nil)
                .accessibilityIdentifier("S2-03-save-retry")
            }
        }
    }

    private func loadExistingSavedSearches() async {
        do {
            let saved = try await savedSearchStore.listSavedSearches(repoPath: repoPath)
            await MainActor.run {
                model.existingNames = Set(saved.map { $0.name.lowercased() })
            }
        } catch {
            let mapped = await mapError(error)
            await MainActor.run {
                model.saveFailure = mapped
            }
        }
    }

    @MainActor
    private func save() async {
        guard model.canSave else { return }
        model.isSaving = true
        model.saveFailure = nil
        do {
            let saved = try await savedSearchStore.createSavedSearch(
                repoPath: repoPath,
                request: model.createRequest
            )
            model.isSaving = false
            onSaved(saved)
        } catch {
            model.isSaving = false
            model.saveFailure = await mapError(error)
        }
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

struct SmartListManagementSheet: View {
    let route: SmartListManagementRoute
    let repoPath: String
    let savedSearches: [SavedSearchSnapshot]
    let resultCountState: SavedSearchResultCountState
    let savedSearchStore: any CoreSavedSearchCRUD
    let searchQuerying: any CoreSearchQuerying
    let errorMapper: any CoreErrorMapping
    let onCancel: () -> Void
    let onSaved: (SavedSearchSnapshot) -> Void
    let onDeleted: (SavedSearchSnapshot) -> Void
    let onEditFilters: (SavedSearchSnapshot, SearchFilterStateSnapshot) -> Void
    @State private var model: SmartListEditorModel

    init(
        route: SmartListManagementRoute,
        repoPath: String,
        savedSearches: [SavedSearchSnapshot],
        resultCountState: SavedSearchResultCountState = .loading,
        savedSearchStore: any CoreSavedSearchCRUD = CoreBridge(),
        searchQuerying: any CoreSearchQuerying = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onCancel: @escaping () -> Void,
        onSaved: @escaping (SavedSearchSnapshot) -> Void,
        onDeleted: @escaping (SavedSearchSnapshot) -> Void,
        onEditFilters: @escaping (SavedSearchSnapshot, SearchFilterStateSnapshot) -> Void
    ) {
        self.route = route
        self.repoPath = repoPath
        self.savedSearches = savedSearches
        self.resultCountState = resultCountState
        self.savedSearchStore = savedSearchStore
        self.searchQuerying = searchQuerying
        self.errorMapper = errorMapper
        self.onCancel = onCancel
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.onEditFilters = onEditFilters
        _model = State(initialValue: SmartListEditorModel(
            mode: route.mode,
            savedSearch: route.savedSearch,
            existingNames: Set(savedSearches.map { $0.name.lowercased() }),
            resultCountState: resultCountState,
            draftFilters: route.draftFilters
        ))
    }

    var body: some View {
        MainFileActionSheetContainer(title: route.mode.title, pageID: "S2-06", content: { content })
        .accessibilityIdentifier("S2-06-smart-list-management")
        .task(id: model.queryDiagnosticTaskKey) {
            await refreshQueryDiagnostic()
        }
    }

    @MainActor
    func submit() async {
        guard model.canSubmit else { return }
        model.isSaving = true
        model.failure = nil
        do {
            switch model.mode {
            case .rename, .editQuery:
                let request = model.updateRequest
                let saved = try await savedSearchStore.updateSavedSearch(repoPath: repoPath, request: request)
                model.isSaving = false
                onSaved(saved)
            case .duplicate:
                let request = model.createRequest
                let saved = try await savedSearchStore.createSavedSearch(repoPath: repoPath, request: request)
                model.isSaving = false
                onSaved(saved)
            case .delete:
                try await savedSearchStore.deleteSavedSearch(repoPath: repoPath, savedSearchID: model.original.id)
                model.isSaving = false
                onDeleted(model.original)
            }
        } catch {
            model.isSaving = false
            model.failure = await mapError(error)
        }
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    @MainActor
    private func refreshQueryDiagnostic() async {
        guard model.mode == .editQuery else { return }
        model.clearQueryDiagnostic()
        let request = model.queryDiagnosticRequest
        guard !request.query.isEmpty || !request.filters.isEmpty else { return }

        model.isCheckingQuery = true
        defer { model.isCheckingQuery = false }
        do {
            let page = try await searchQuerying.searchFiles(repoPath: repoPath, request: request)
            guard !Task.isCancelled else { return }
            model.applyQueryDiagnosticPage(page)
        } catch {
            guard !Task.isCancelled else { return }
            model.markQueryDiagnosticUnavailable()
        }
    }
}

private extension SmartListManagementSheet {
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
