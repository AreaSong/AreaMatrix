enum MainRepositoryNoteDraftRouting {
    @MainActor
    static func showFailedDraftBannerIfNeeded(
        leaving previousSelection: Set<Int64>,
        noteModel: DetailNoteModel,
        listModel: MainFileListModel
    ) {
        guard previousSelection.count == 1, let fileID = previousSelection.first else { return }
        guard let failedFileID = noteModel.failedDraftFileIDLeaving(fileID: fileID) else { return }
        listModel.showUnsavedNoteDraftPreserved(fileID: failedFileID)
    }
}
