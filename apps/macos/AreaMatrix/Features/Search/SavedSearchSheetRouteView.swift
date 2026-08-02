import SwiftUI

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
        .accessibilityIdentifier("saved-search-saved-search-preview")
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
        savedSearchStore: any CoreSavedSearchCRUD,
        errorMapper: any CoreErrorMapping,
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
        MainFileActionSheetContainer(title: L10n.string("Save Search"), pageID: "saved-search") {
            Text(L10n.string("Save the current query as a Smart List. Files are not moved or duplicated."))
                .font(.callout)
                .foregroundStyle(.secondary)
            savedSearchErrorView
            TextField(L10n.string("Name"), text: $model.name)
                .textFieldStyle(.roundedBorder)
                .disabled(model.isSaving)
                .accessibilityIdentifier("saved-search-saved-search-name")
            Picker(L10n.string("Icon"), selection: $model.icon) {
                ForEach(SavedSearchSheetModel.icons, id: \.self) { icon in
                    Label(icon, systemImage: icon).tag(icon)
                }
            }
            .disabled(model.isSaving)
            Toggle(L10n.string("Pin to sidebar"), isOn: $model.pinned)
                .disabled(model.isSaving)
            SavedSearchPreview(model: model)
            HStack {
                Button(L10n.string("Edit filters"), action: onEditFilters)
                    .disabled(model.isSaving)
                Spacer()
                Button(L10n.string("Cancel")) {
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
            Button(L10n.string("Continue Saving"), role: .cancel) {}
        }
        .task {
            await loadExistingSavedSearches()
        }
        .accessibilityIdentifier("saved-search-search-route")
    }

    @ViewBuilder
    private var savedSearchErrorView: some View {
        if let validationMessage = model.validationMessage {
            Label(validationMessage, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityIdentifier("saved-search-validation-error")
        }
        if let failure = model.saveFailure {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("saved-search-save-error")
                Spacer()
                Button(L10n.string("Retry")) {
                    Task { await save() }
                }
                .disabled(!model.showsRetry || model.validationMessage != nil)
                .accessibilityIdentifier("saved-search-save-retry")
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
            let mapped = await errorMapper.mapError(error)
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
            model.saveFailure = await errorMapper.mapError(error)
        }
    }
}
