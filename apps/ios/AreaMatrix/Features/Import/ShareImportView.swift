import SwiftUI

struct ShareImportView: View {
    @StateObject private var model: ShareImportModel
    private let onCancel: () -> Void
    private let onOpenAreaMatrix: () -> Void
    private let onSaved: (ShareImportResult) -> Void

    init(
        model: ShareImportModel,
        onCancel: @escaping () -> Void,
        onOpenAreaMatrix: @escaping () -> Void,
        onSaved: @escaping (ShareImportResult) -> Void
    ) {
        _model = StateObject(wrappedValue: model)
        self.onCancel = onCancel
        self.onOpenAreaMatrix = onOpenAreaMatrix
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            List {
                objectSection
                targetSection
                detailsSection
                statusSection
            }
            .navigationTitle("Save to AreaMatrix")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.saveButtonTitle) {
                        Task { await model.save() }
                    }
                    .disabled(!model.canSave)
                }
            }
            .task {
                await model.prepare()
            }
            .onChange(of: model.result) { _, result in
                if let result {
                    onSaved(result)
                }
            }
        }
    }

    private var objectSection: some View {
        Section {
            Label(model.objectSummary, systemImage: objectIcon)
                .lineLimit(2)
            if model.payload.readableItems.count > 1 {
                LabeledContent("Total size", value: model.totalSizeText)
                ForEach(model.payload.readableItems.prefix(3)) { item in
                    Text(item.displayName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var targetSection: some View {
        Section {
            LabeledContent("Repository", value: model.repositoryName)
            TextField("Category", text: Binding(
                get: { model.category },
                set: { model.updateCategory($0) }
            ))
            .autocorrectionDisabled()
        }
    }

    private var detailsSection: some View {
        Section {
            if model.allowsFilenameEditing {
                TextField("File name", text: $model.filename)
                    .autocorrectionDisabled()
                if let validation = model.filenameValidation {
                    Text(validation)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                LabeledContent("File name", value: model.filename)
            }
            Text("AreaMatrix will copy these items into the repository after you confirm.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Import may continue in AreaMatrix.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Section {
            Label(model.statusText, systemImage: statusIcon)
                .foregroundStyle(statusColor)
            if let warning = model.warning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error = model.error {
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if model.shouldOfferOpenApp {
                Button("Open AreaMatrix", action: onOpenAreaMatrix)
            }
        }
    }

    private var objectIcon: String {
        model.payload.readableItems.count > 1 ? "doc.on.doc" : "doc"
    }

    private var statusIcon: String {
        switch model.phase {
        case .reading, .saving:
            "arrow.triangle.2.circlepath"
        case .ready:
            "checkmark"
        case .saved:
            "checkmark.circle"
        case .empty, .failed, .permissionRequired:
            "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .saved:
            .green
        case .empty, .failed, .permissionRequired:
            .orange
        case .reading, .ready, .saving:
            .secondary
        }
    }
}
