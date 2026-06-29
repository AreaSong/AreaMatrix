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
}
