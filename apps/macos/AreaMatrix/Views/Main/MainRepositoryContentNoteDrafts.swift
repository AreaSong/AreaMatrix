import Foundation
import SwiftUI

extension MainRepositoryContentView {
    @MainActor
    func showFailedNoteDraftBannerIfNeeded(leaving previousSelection: Set<Int64>) {
        guard previousSelection.count == 1, let fileID = previousSelection.first else { return }
        guard let failedFileID = detailNoteModel.failedDraftFileIDLeaving(fileID: fileID) else { return }
        fileListModel.showUnsavedNoteDraftPreserved(fileID: failedFileID)
    }

    func showUnsavedNoteDraftPreserved(fileID: Int64) {
        fileListModel.showUnsavedNoteDraftPreserved(fileID: fileID)
    }

    var detailPane: some View {
        MainRepositoryDetailPane(
            selection: fileListModel.selection,
            multiSelectionSummary: MultiSelectionDetailSummary(
                selection: fileListModel.selection,
                files: visibleFiles,
                isUpdating: fileListModel.isLoading || fileListModel.isDetailLoading
            ),
            detailErrorMapping: fileListModel.detailErrorMapping,
            isDetailLoading: fileListModel.isDetailLoading,
            selectedFileDetail: fileListModel.selectedFileDetail,
            noteWriteBlock: fileListModel.selectedFileNoteWriteBlock,
            detailLogState: fileListModel.detailLogState,
            detailLogDiagnosticsState: fileListModel.detailLogDiagnosticsState,
            detailExternalCreateSyncState: fileListModel.detailExternalCreateSyncState,
            detailTabRequest: fileListModel.detailTabRequest,
            selectedImportProgressRow: selectedImportProgressRow,
            onRetrySelectedFileDetail: {
                Task {
                    await fileListModel.retrySelectedFileDetail()
                }
            },
            onCopyPaths: onCopyPaths,
            onOpenNoteFile: onOpenNoteFile,
            onRefreshChangeLog: {
                Task {
                    await fileListModel.loadSelectedFileChangeLog()
                }
            },
            onRequestDetailLogDiagnostics: fileListModel.requestDetailLogDiagnosticsPrivacyConfirmation,
            onConfirmDetailLogDiagnostics: {
                Task {
                    await fileListModel.collectDetailLogDiagnostics()
                }
            },
            onCancelDetailLogDiagnostics: fileListModel.cancelDetailLogDiagnosticsPrivacyConfirmation,
            onDetailTabRequestConsumed: fileListModel.consumeDetailTabRequest,
            onBeginRenameFile: fileListModel.beginRename,
            onBeginChangeCategoryFile: fileListModel.beginChangeCategory,
            onBeginDeleteFile: fileListModel.beginDelete,
            onBeginICloudConflictResolution: fileListModel.beginICloudConflictResolution,
            writeActionDisabledReason: fileListModel.writeActionDisabledReason,
            noteModel: detailNoteModel
        )
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, maxHeight: .infinity, alignment: .topLeading)
    }
}
