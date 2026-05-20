import SwiftUI

struct MainFileActionRoutingSheet: View {
    let destination: MainFileActionDestination
    let file: FileEntrySnapshot?
    let candidateFiles: [FileEntrySnapshot]
    let categoryRows: [RepositorySidebarRowSnapshot]
    let renameState: MainFileRenameState
    let deleteState: MainFileDeleteState
    let changeCategoryState: MainFileCategoryMoveState
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
    let onChangeCategory: (Int64, String) -> Void
    let onRenameFirstFromChangeCategory: (Int64, String) -> Void
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
            ChangeCategorySheet(
                file: file,
                categoryRows: categoryRows,
                state: changeCategoryState,
                initialTargetCategory: destination.initialChangeCategoryTarget,
                onCancel: onDismiss,
                onPreview: onPreviewChangeCategory,
                onChangeCategory: onChangeCategory,
                onRenameFirst: onRenameFirstFromChangeCategory,
                onOpenPermissionRecovery: onOpenChangeCategoryPermissionRecovery,
                onCollectDiagnostics: onCollectDiagnostics
            )
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
}

extension ICloudConflictVersionSnapshot {
    static func originalCandidate(repoPath: String, file: FileEntrySnapshot?) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: .original,
            path: file.flatMap { originalCandidatePath(repoPath: repoPath, file: $0) },
            modifiedAt: file?.updatedAt,
            sizeBytes: nil
        )
    }

    static func conflictedCandidate(repoPath: String, file: FileEntrySnapshot?) -> ICloudConflictVersionSnapshot {
        ICloudConflictVersionSnapshot(
            role: .conflictedCopy,
            path: file.map { absolutePath(repoPath: repoPath, relativePath: $0.path) },
            modifiedAt: file?.updatedAt,
            sizeBytes: file?.sizeBytes
        )
    }

    private static func originalCandidatePath(repoPath: String, file: FileEntrySnapshot) -> String {
        let relativePath = file.path.replacingOccurrences(of: " (Conflicted Copy)", with: "")
        return absolutePath(repoPath: repoPath, relativePath: relativePath)
    }

    private static func absolutePath(repoPath: String, relativePath: String) -> String {
        URL(fileURLWithPath: repoPath, isDirectory: true)
            .appendingPathComponent(relativePath)
            .path
    }
}

struct MainFileActionSheetContainer<Content: View>: View {
    let title: String
    let pageID: String
    private let content: Content

    init(title: String, pageID: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.pageID = pageID
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(22)
        .frame(width: 420, alignment: .leading)
        .accessibilityIdentifier("\(pageID)-file-action-sheet")
    }
}

struct MissingFileActionContext: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("The selected file context is no longer available.")
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
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

    init(
        request: SearchQueryRequestSnapshot,
        repoPath: String = "",
        resultCount: Int64?,
        savedSearchStore: any CoreSavedSearchCRUD = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        onCancel: @escaping () -> Void,
        onSaved: @escaping (SavedSearchSnapshot) -> Void = { _ in },
        onEditFilters: @escaping () -> Void = {}
    ) {
        self.init(
            request: request,
            repoPath: repoPath,
            resultCountState: resultCount.map(SavedSearchResultCountState.loaded) ?? .loading,
            savedSearchStore: savedSearchStore,
            errorMapper: errorMapper,
            onCancel: onCancel,
            onSaved: onSaved,
            onEditFilters: onEditFilters
        )
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
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

func metadataRow(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(value)
            .font(.callout)
            .textSelection(.enabled)
    }
}
