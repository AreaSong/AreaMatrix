import SwiftUI

struct DeleteFileConfirmSheet: View {
    let file: FileEntrySnapshot?
    let operation: MainFileDeleteOperation?
    let state: MainFileDeleteState
    let isTrashAvailable: Bool
    let onCancel: () -> Void
    let onConfirm: (Int64, MainFileDeleteOperation) -> Void
    let onCollectDiagnostics: () -> Void
    @State private var isConfirmed = false

    var body: some View {
        MainFileActionSheetContainer(title: operation?.title ?? "Move File to Trash?", pageID: "S1-34") {
            if let file, let operation {
                VStack(alignment: .leading, spacing: 12) {
                    Text(operation.message)
                        .foregroundStyle(.secondary)
                    if operation == .moveToTrash {
                        deleteImpactText
                    }
                    metadataRow("Name", file.currentName)
                    metadataRow("Location", file.path)
                    metadataRow("Storage mode", file.storageMode)
                    metadataRow("Status", file.statusDisplay)
                    operationStatus(file: file, operation: operation)
                    Toggle(operation.confirmationText, isOn: $isConfirmed)
                        .disabled(state.isDeleting(fileID: file.id))
                    actionButtons(file: file, operation: operation)
                }
            } else {
                MissingFileActionContext(onCancel: onCancel)
            }
        }
    }

    private var deleteImpactText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The file is recoverable from system Trash while Trash retains it.")
            Text("AreaMatrix keeps a deleted metadata record for at least 30 days for traceability.")
            Text("Permanent delete is not available in Stage 1.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func operationStatus(file: FileEntrySnapshot, operation: MainFileDeleteOperation) -> some View {
        if state.isDeleting(fileID: file.id) {
            Label(operation.runningTitle, systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let failure = state.failure(for: file.id) {
            failureView(failure, operation: operation)
        } else if operation == .moveToTrash, !isTrashAvailable {
            Label("Trash is not available. Handle the file in Finder or collect diagnostics.", systemImage: "trash.slash")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func failureView(
        _ failure: CoreErrorMappingSnapshot,
        operation: MainFileDeleteOperation
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(operation.failureTitle, systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(failure.userMessage)
                .font(.caption)
            Text(failure.suggestedAction)
                .font(.caption)
            Text(failure.rawContext)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Button("Collect Diagnostics...", action: onCollectDiagnostics)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(Color.yellow.opacity(0.12))
    }

    private func actionButtons(file: FileEntrySnapshot, operation: MainFileDeleteOperation) -> some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(state.isDeleting(fileID: file.id))
            Button(actionTitle(file: file, operation: operation), role: .destructive) {
                onConfirm(file.id, operation)
            }
            .disabled(actionDisabled(file: file, operation: operation))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func actionTitle(file: FileEntrySnapshot, operation: MainFileDeleteOperation) -> String {
        state.primaryActionTitle(fileID: file.id, operation: operation)
    }

    private func actionDisabled(file: FileEntrySnapshot, operation: MainFileDeleteOperation) -> Bool {
        if state.isDeleting(fileID: file.id) { return true }
        if !isConfirmed { return true }
        return operation == .moveToTrash && !isTrashAvailable
    }
}
