import SwiftUI

struct ChangeCategorySheet: View {
    let file: FileEntrySnapshot?
    let categoryRows: [RepositorySidebarRowSnapshot]
    let state: MainFileCategoryMoveState
    let onCancel: () -> Void
    let onPreview: (Int64, String) -> Void
    let onChangeCategory: (Int64, String) -> Void
    let onRenameFirst: (Int64) -> Void
    let onCollectDiagnostics: () -> Void
    @State private var targetCategory: String

    init(
        file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot],
        state: MainFileCategoryMoveState,
        onCancel: @escaping () -> Void,
        onPreview: @escaping (Int64, String) -> Void,
        onChangeCategory: @escaping (Int64, String) -> Void,
        onRenameFirst: @escaping (Int64) -> Void,
        onCollectDiagnostics: @escaping () -> Void
    ) {
        self.file = file
        self.categoryRows = categoryRows
        self.state = state
        self.onCancel = onCancel
        self.onPreview = onPreview
        self.onChangeCategory = onChangeCategory
        self.onRenameFirst = onRenameFirst
        self.onCollectDiagnostics = onCollectDiagnostics
        _targetCategory = State(initialValue: Self.defaultTargetCategory(for: file, categoryRows: categoryRows))
    }

    var body: some View {
        MainFileActionSheetContainer(title: "Change Category", pageID: "S1-35") {
            if let file {
                VStack(alignment: .leading, spacing: 12) {
                    metadataRow("Name", file.currentName)
                    metadataRow("Current category", file.categoryPathDisplay)
                    metadataRow("Storage mode", file.storageMode)
                    Picker("Target category", selection: $targetCategory) {
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    metadataRow("Target path", targetPathText(for: file))
                    statusView(for: file)
                    actionButtons(for: file)
                }
                .task(id: previewTaskID(for: file)) {
                    requestPreviewIfNeeded(for: file)
                }
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
    }

    private func targetPathText(for file: FileEntrySnapshot) -> String {
        let request = previewRequest(for: file)
        if let preview = state.preview(for: request) {
            return preview.targetPath
        }
        if targetCategory == file.category {
            return file.path
        }
        if state.isChecking(request) {
            return "Checking destination..."
        }
        return "\(targetCategory)/\(file.currentName)"
    }

    @ViewBuilder
    private func statusView(for file: FileEntrySnapshot) -> some View {
        let request = previewRequest(for: file)
        if targetCategory == file.category {
            statusLabel("Choose a different category", systemImage: "info.circle", color: .secondary)
        } else if state.isChecking(request) {
            statusLabel("Checking destination...", systemImage: "arrow.triangle.2.circlepath", color: .secondary)
        } else if state.isMoving(fileID: file.id) {
            statusLabel("Moving...", systemImage: "arrow.triangle.2.circlepath", color: .secondary)
        } else if let failure = state.failure(for: file.id, targetCategory: targetCategory) {
            failureView(failure, file: file)
        } else if let preview = state.preview(for: request) {
            previewStatus(preview)
        }
    }

    private func actionButtons(for file: FileEntrySnapshot) -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(state.isMoving(fileID: file.id))
            Button(primaryActionTitle(for: file)) {
                onChangeCategory(file.id, targetCategory)
            }
                .disabled(actionDisabled(for: file))
                .keyboardShortcut(.defaultAction)
        }
    }

    private func failureView(_ failure: CoreErrorMappingSnapshot, file: FileEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(failureMessage(failure, file: file), systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(failure.suggestedAction)
                .font(.caption)
            Text(failure.rawContext)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            failureActions(for: file)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(Color.yellow.opacity(0.12))
    }

    private func failureActions(for file: FileEntrySnapshot) -> some View {
        HStack {
            if hasUnresolvedNameConflict(for: file) {
                Button("Rename first") {
                    onRenameFirst(file.id)
                }
            }
            if state.failureOperation(for: file.id, targetCategory: targetCategory) == .preview {
                Button("Retry preview") {
                    onPreview(file.id, targetCategory)
                }
            }
            Button("Collect Diagnostics...", action: onCollectDiagnostics)
        }
    }

    private func previewStatus(_ preview: MoveToCategoryPreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if preview.indexOnly {
                statusLabel(
                    "Index-only: AreaMatrix updates category metadata and change log only.",
                    systemImage: "link",
                    color: .secondary
                )
            } else if preview.nameConflictResolved {
                statusLabel(
                    "Target name exists. AreaMatrix will use \(preview.targetName).",
                    systemImage: "number",
                    color: .secondary
                )
            } else {
                statusLabel("No conflict at target location", systemImage: "checkmark.circle", color: .green)
            }
        }
    }

    private func statusLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func previewTaskID(for file: FileEntrySnapshot) -> String {
        "\(file.id)-\(targetCategory)"
    }

    private func requestPreviewIfNeeded(for file: FileEntrySnapshot) {
        guard targetCategory != file.category, !targetCategory.isEmpty else { return }
        onPreview(file.id, targetCategory)
    }

    private func previewRequest(for file: FileEntrySnapshot) -> MainFileCategoryMovePreviewRequest {
        MainFileCategoryMovePreviewRequest(fileID: file.id, targetCategory: targetCategory)
    }

    private func primaryActionTitle(for file: FileEntrySnapshot) -> String {
        if state.isMoving(fileID: file.id) {
            return "Moving..."
        }
        if state.failureOperation(for: file.id, targetCategory: targetCategory) == .move {
            return "Retry"
        }
        return "Change Category"
    }

    private func actionDisabled(for file: FileEntrySnapshot) -> Bool {
        if targetCategory == file.category || state.isChecking(fileID: file.id, targetCategory: targetCategory) {
            return true
        }
        if state.isMoving(fileID: file.id) {
            return true
        }
        let request = previewRequest(for: file)
        if state.preview(for: request) != nil {
            return false
        }
        return state.failureOperation(for: file.id, targetCategory: targetCategory) != .move
    }

    private func failureMessage(_ failure: CoreErrorMappingSnapshot, file: FileEntrySnapshot) -> String {
        if hasUnresolvedNameConflict(for: file) {
            return "Cannot create a safe target name. Rename the file first."
        }
        return failure.userMessage
    }

    private func hasUnresolvedNameConflict(for file: FileEntrySnapshot) -> Bool {
        state.unresolvedNameConflict(for: file.id, targetCategory: targetCategory) != nil
    }

    private var availableCategories: [String] {
        MainFileActionCategoryOptions.availableCategories(file: file, categoryRows: categoryRows)
    }

    private static func defaultTargetCategory(
        for file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> String {
        MainFileActionCategoryOptions.defaultTargetCategory(for: file, categoryRows: categoryRows)
    }
}
