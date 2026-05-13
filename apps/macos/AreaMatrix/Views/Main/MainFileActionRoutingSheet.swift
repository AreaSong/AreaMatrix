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
