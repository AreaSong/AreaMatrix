import SwiftUI

struct MainRepositoryMultiSelectionActions: View {
    let selection: MainFileSelectionState
    let summary: MultiSelectionDetailSummary
    let detailErrorMapping: CoreErrorMappingSnapshot?
    let repoPath: String
    let categoryRows: [RepositorySidebarRowSnapshot]
    let batchTagStore: any CoreTagCRUD
    let batchTagUndoStore: any CoreUndoActionLogging
    let batchTagErrorMapper: any CoreErrorMapping
    let batchDeleter: any CoreBatchDeleting
    let batchCategoryChanger: any CoreBatchCategoryChanging
    let batchRenamer: any CoreBatchRenaming
    let tagActions: MainRepositoryDetailPaneTagActions
    let writeActionDisabledReason: (Int64) -> MainFileWriteActionDisabledReason?
    let onCopyPaths: ([String]) -> Void
    let onRetrySelectedFileDetail: () -> Void
    let onRefreshChangeLog: () -> Void
    let onBatchCategoryApplied: (BatchCategoryChangeReportSnapshot) -> Void
    let onBatchDeleteApplied: (BatchDeleteReportSnapshot) -> Void
    let onBatchRenameApplied: (BatchRenameReportSnapshot) -> Void
    let onBatchCategoryCreateNewCategory: (BatchChangeCategoryNewCategoryHandoff) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Show in Finder") {}
                .disabled(true)
                .help("Open one file at a time")
            Text("Open one file at a time")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Copy Paths") {
                onCopyPaths(summary.paths)
            }
            .disabled(summary.paths.isEmpty)
            BatchAddTagsTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedCount: summary.selectedCount,
                disabledReason: batchAddTagsDisabledReason,
                tagStore: batchTagStore,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onRefreshSelection: onRetrySelectedFileDetail,
                onRefreshChangeLog: onRefreshChangeLog,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            BatchChangeCategoryTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchChangeCategoryDisabledReason,
                categoryRows: categoryRows,
                changer: batchCategoryChanger,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchCategoryApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange,
                onCreateNewCategory: onBatchCategoryCreateNewCategory
            )
            BatchRenameTrigger(
                repoPath: repoPath,
                fileIDs: BatchRenameEntryPolicy.fileIDsForPreview(summary: summary),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchRenameDisabledReason,
                renamer: batchRenamer,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchRenameApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            BatchDeleteTrigger(
                repoPath: repoPath,
                fileIDs: selection.multipleFileIDs.sorted(),
                selectedFiles: summary.files,
                selectedCount: summary.selectedCount,
                disabledReason: batchDeleteDisabledReason,
                deleter: batchDeleter,
                undoStore: batchTagUndoStore,
                errorMapper: batchTagErrorMapper,
                onApplied: onBatchDeleteApplied,
                onUndoStateChange: tagActions.onBatchTagUndoStateChange
            )
            if detailErrorMapping != nil {
                Button("Retry Metadata", action: onRetrySelectedFileDetail)
            }
        }
    }

    private var batchAddTagsDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if let reason = summary.files.compactMap({ writeActionDisabledReason($0.id) }).first {
            return reason.rawValue
        }
        return nil
    }

    private var batchChangeCategoryDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if let reason = summary.files.compactMap({ writeActionDisabledReason($0.id) }).first {
            return reason.rawValue
        }
        return nil
    }

    private var batchDeleteDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if summary.isUpdating { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        if let reason = summary.files.compactMap({ writeActionDisabledReason($0.id) }).first {
            return reason.rawValue
        }
        return nil
    }

    private var batchRenameDisabledReason: String? {
        if summary.selectedCount == 0 { return "No files selected" }
        if summary.isUpdating { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        if let reason = summary.files.compactMap({ writeActionDisabledReason($0.id) }).first {
            return reason.rawValue
        }
        return nil
    }
}

extension MainRepositoryContentView {
    func openBatchChangeCategoryRoute(_ ids: Set<Int64>, source: BatchChangeCategoryRouteSource) {
        let selectedFiles = filesForBatchChangeCategory(ids)
        pendingBatchChangeCategoryRoute = BatchChangeCategoryRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchChangeCategoryDisabledReason(for: selectedFiles)
        )
    }

    func openBatchDeleteRoute(_ ids: Set<Int64>, source: BatchDeleteRouteSource) {
        let selectedFiles = filesForBatchDelete(ids)
        pendingBatchDeleteRoute = BatchDeleteRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchDeleteDisabledReason(for: selectedFiles)
        )
    }

    func openBatchRenameRoute(_ ids: Set<Int64>, source: BatchRenameRouteSource) {
        let selectedFiles = filesForBatchRename(ids)
        pendingBatchRenameRoute = BatchRenameRoute(
            source: source,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchRenameDisabledReason(for: selectedFiles)
        )
    }

    func commandPaletteBatchChangeCategoryRoute() -> BatchChangeCategoryRoute {
        let selectedFiles = filesForBatchChangeCategory(selectedFileIDs)
        return BatchChangeCategoryRoute(
            source: .commandPalette,
            fileIDs: selectedFiles.map(\.id),
            selectedFiles: selectedFiles,
            selectedCount: selectedFiles.count,
            disabledReason: batchChangeCategoryDisabledReason(for: selectedFiles)
        )
    }

    private func filesForBatchChangeCategory(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { ids.contains($0.id) }
    }

    func filesForBatchDelete(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { ids.contains($0.id) }
    }

    func filesForBatchRename(_ ids: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { ids.contains($0.id) }
    }

    private func batchChangeCategoryDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchChangeCategoryEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    func batchDeleteDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchDeleteEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    func batchRenameDisabledReason(for files: [FileEntrySnapshot]) -> String? {
        BatchRenameEntryPolicy.disabledReason(
            selectedFiles: files,
            isReadOnly: fileListModel.isReadOnly,
            isLoading: fileListModel.isLoading,
            writeLockedFileIDs: fileListModel.writeLockedFileIDs
        )
    }

    func batchRenameRoutingSheet(_ route: BatchRenameRoute) -> some View {
        BatchRenameSheet(
            repoPath: opening.config.repoPath,
            fileIDs: route.fileIDs,
            selectedFiles: route.selectedFiles,
            selectedCount: route.selectedCount,
            disabledReason: route.disabledReason,
            renamer: batchRenamer,
            undoStore: fileListModel.undoActionStore,
            errorMapper: fileListModel.errorMapper,
            onApplied: applyBatchRenameResult,
            onUndoStateChange: updateBatchTagUndoState,
            onClose: { pendingBatchRenameRoute = nil }
        )
    }

    func applyBatchRenameResult(_ report: BatchRenameReportSnapshot) {
        Task {
            if !report.updatedFiles.isEmpty {
                fileListModel.files = fileListModel.files.map { current in
                    report.updatedFiles.first { $0.id == current.id } ?? current
                }
            }
            await fileListModel.retryCurrentCategory()
            await fileListModel.retrySelectedFileDetail()
        }
    }
}

enum CommandPaletteBatchRouteBuilder {
    static func batchDeleteRoute(
        selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> BatchDeleteRoute {
        let files = selectedFiles(selectedFileIDs, visibleFiles: visibleFiles)
        return BatchDeleteRoute(
            source: .commandPalette,
            fileIDs: files.map(\.id),
            selectedFiles: files,
            selectedCount: files.count,
            disabledReason: BatchDeleteEntryPolicy.disabledReason(
                selectedFiles: files,
                isReadOnly: isReadOnly,
                isLoading: isLoading,
                writeLockedFileIDs: writeLockedFileIDs
            )
        )
    }

    static func batchRenameRoute(
        selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> BatchRenameRoute {
        let files = selectedFiles(selectedFileIDs, visibleFiles: visibleFiles)
        return BatchRenameRoute(
            source: .commandPalette,
            fileIDs: files.map(\.id),
            selectedFiles: files,
            selectedCount: files.count,
            disabledReason: BatchRenameEntryPolicy.disabledReason(
                selectedFiles: files,
                isReadOnly: isReadOnly,
                isLoading: isLoading,
                writeLockedFileIDs: writeLockedFileIDs
            )
        )
    }

    private static func selectedFiles(
        _ selectedFileIDs: Set<Int64>,
        visibleFiles: [FileEntrySnapshot]
    ) -> [FileEntrySnapshot] {
        visibleFiles.filter { selectedFileIDs.contains($0.id) }
    }
}
