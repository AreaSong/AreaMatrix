import SwiftUI

struct MainFileActionRoutingSheet: View {
    let destination: MainFileActionDestination
    let file: FileEntrySnapshot?
    let candidateFiles: [FileEntrySnapshot]
    let categoryRows: [RepositorySidebarRowSnapshot]
    let renameState: MainFileRenameState
    let deleteState: MainFileDeleteState
    let changeCategoryState: MainFileCategoryMoveState
    let isTrashAvailable: Bool
    let onDismiss: () -> Void
    let onRename: (Int64, String) -> Void
    let onShowExistingFile: (Int64) -> Void
    let onPreviewChangeCategory: (Int64, String) -> Void
    let onChangeCategory: (Int64, String) -> Void
    let onDelete: (Int64, MainFileDeleteOperation) -> Void
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
                onCancel: onDismiss,
                onPreview: onPreviewChangeCategory,
                onChangeCategory: onChangeCategory,
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
        }
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
