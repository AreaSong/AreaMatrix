import SwiftUI

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
