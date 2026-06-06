import SwiftUI

struct FilesImportReviewSheet: View {
    @StateObject private var model: FilesImportReviewModel
    private let onCancel: () -> Void
    private let onImported: ([MobileLibraryFile]) -> Void

    init(
        repoPath: String,
        selectedURLs: [URL],
        bridge: any FilesImportCoreBridge,
        allowReplaceDuringImport: Bool = false,
        onCancel: @escaping () -> Void,
        onImported: @escaping ([MobileLibraryFile]) -> Void
    ) {
        _model = StateObject(wrappedValue: FilesImportReviewModel(
            repoPath: repoPath,
            selectedURLs: selectedURLs,
            bridge: bridge,
            allowReplaceDuringImport: allowReplaceDuringImport
        ))
        self.onCancel = onCancel
        self.onImported = onImported
    }

    var body: some View {
        NavigationStack {
            List {
                sourceSection
                targetSection
                MobileConflictSummary(
                    items: model.previewItems,
                    candidates: model.replaceCandidates,
                    replaceUnavailableReason: model.replaceUnavailableReason,
                    onSelectStrategy: model.updateConflictStrategy(for:strategy:)
                )
                statusSection
            }
            .navigationTitle("Import from Files")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(cancelTitle, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.importButtonTitle) {
                        Task { await model.importFiles() }
                    }
                    .disabled(!model.canImport)
                }
            }
            .task {
                await model.prepare()
            }
            .onChange(of: model.phase) { _, phase in
                if phase == .succeeded {
                    onImported(model.importedFiles)
                }
            }
            .sheet(item: Binding(
                get: { model.pendingReplaceConfirmation },
                set: { newValue in
                    if newValue == nil, model.pendingReplaceConfirmation != nil {
                        model.cancelReplaceConfirmation()
                    }
                }
            )) { confirmation in
                FilesImportReplaceConfirmSheet(
                    confirmation: confirmation,
                    errorMessage: model.replaceErrorMessage,
                    onCancel: model.cancelReplaceConfirmation,
                    onConfirm: { understands in
                        model.confirmReplace(confirmation, understandsReplace: understands)
                    }
                )
            }
        }
    }

    private var sourceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.selectedSummary, systemImage: "doc")
                    .font(.headline)
                Text(model.totalSizeText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            FilesImportPreviewList(items: model.previewItems)
        }
    }

    private var targetSection: some View {
        Section {
            TextField("Target category", text: Binding(
                get: { model.category },
                set: { model.updateCategory($0) }
            ))
            if model.allowsFilenameEditing {
                TextField("File name", text: $model.filename)
                    .autocorrectionDisabled()
                if let message = model.filenameValidation {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                LabeledContent("File names", value: "Keep selected names")
            }
            LabeledContent("Save as", value: "Copy into repository")
        }
    }

    private var statusSection: some View {
        Section {
            ImportProgressView(phase: model.phase, statusText: model.statusText)
            if let warning = model.warning {
                Text(warning)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let error = model.error {
                Text(error.message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("Retry failed") {
                    Task { await model.retry() }
                }
                .disabled(model.phase == .importing)
            }
        }
    }

    private var cancelTitle: String {
        model.phase == .importing ? "Close when done" : "Cancel"
    }
}

private struct FilesImportPreviewList: View {
    let items: [FilesImportPreviewItem]

    var body: some View {
        ForEach(items.prefix(8)) { item in
            HStack(spacing: 12) {
                Image(systemName: icon(for: item.status))
                    .foregroundStyle(color(for: item.status))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.body)
                        .lineLimit(1)
                    Text("\(item.sourceLocation) · \(item.sizeText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(item.status.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color(for: item.status))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.displayName), \(item.status.label), \(item.sizeText)")
        }
    }

    private func icon(for status: FilesImportPreviewStatus) -> String {
        switch status {
        case .ready:
            "doc"
        case .unreadable, .downloadNeeded, .failed:
            "exclamationmark.triangle"
        case .importing:
            "arrow.triangle.2.circlepath"
        case .imported:
            "checkmark.circle"
        case .skippedDuplicate:
            "minus.circle"
        }
    }

    private func color(for status: FilesImportPreviewStatus) -> Color {
        switch status {
        case .ready, .importing:
            .secondary
        case .imported:
            .green
        case .skippedDuplicate:
            .blue
        case .unreadable, .downloadNeeded, .failed:
            .orange
        }
    }
}

private struct MobileConflictSummary: View {
    let items: [FilesImportPreviewItem]
    let candidates: [FilesImportReplaceCandidate]
    let replaceUnavailableReason: String?
    let onSelectStrategy: (FilesImportReplaceCandidate.ID, FilesImportConflictStrategy) -> Void

    var body: some View {
        if !candidateRows.isEmpty || !conflictRows.isEmpty {
            Section("Conflicts") {
                ForEach(candidateRows) { candidate in
                    FilesImportConflictCandidateRow(
                        candidate: candidate,
                        replaceUnavailableReason: replaceUnavailableReason,
                        onSelectStrategy: onSelectStrategy
                    )
                }
                ForEach(conflictRows, id: \.self) { row in
                    Label(row, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                Text("Duplicate content uses Skip duplicate. Name conflicts use Keep both. Replace requires confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var candidateRows: [FilesImportReplaceCandidate] {
        candidates
    }

    private var conflictRows: [String] {
        items.compactMap { item in
            switch item.status {
            case let .skippedDuplicate(existingPath):
                return "Duplicate content: \(existingPath)"
            case .downloadNeeded:
                return "Download needed: \(item.displayName)"
            case .unreadable:
                return "Unreadable: \(item.displayName)"
            case let .failed(message):
                return "\(item.displayName): \(message)"
            case .ready, .importing, .imported:
                return nil
            }
        }
    }
}

private struct ImportProgressView: View {
    var phase: FilesImportPhase
    var statusText: String

    var body: some View {
        Label(statusText, systemImage: icon)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .accessibilityLabel(statusText)
    }

    private var icon: String {
        switch phase {
        case .reading, .importing:
            "arrow.triangle.2.circlepath"
        case .ready:
            "checkmark"
        case .succeeded:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch phase {
        case .succeeded:
            .green
        case .failed:
            .orange
        case .reading, .ready, .importing:
            .secondary
        }
    }
}
