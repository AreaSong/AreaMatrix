struct MainFileActionRoutingState {
    var batchAddTagsRoute: BatchAddTagsRoute?
    var batchChangeCategoryRoute: BatchChangeCategoryRoute?
    var batchDeleteRoute: BatchDeleteRoute?
    var batchRenameRoute: BatchRenameRoute?
    var undoHistoryRequest: UndoToastHistoryRequest?
    var batchTagUndoState: BatchTagUndoState = .idle
    var actionLogRefreshFailure: CoreErrorMappingSnapshot?
}
