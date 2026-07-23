import Foundation

struct BatchDeleteRoute: Identifiable, Equatable {
    let source: MainFileBatchActionRouteSource
    private let payload: MainFileBatchActionRoutePayload

    var fileIDs: [Int64] {
        payload.fileIDs
    }

    var selectedFiles: [FileEntrySnapshot] {
        payload.selectedFiles
    }

    var selectedCount: Int {
        payload.selectedCount
    }

    var disabledReason: String? {
        payload.disabledReason
    }

    var id: String {
        ([source.rawValue] + payload.identityParts).joined(separator: ":")
    }

    init(
        source: MainFileBatchActionRouteSource,
        fileIDs: [Int64],
        selectedFiles: [FileEntrySnapshot],
        selectedCount: Int,
        disabledReason: String?
    ) {
        self.source = source
        payload = MainFileBatchActionRoutePayload(
            fileIDs: fileIDs,
            selectedFiles: selectedFiles,
            selectedCount: selectedCount,
            disabledReason: disabledReason
        )
    }
}

extension BatchDeleteRoute {
    init(source: MainFileBatchActionRouteSource, context: MainFileBatchActionRouteContext) {
        self.init(source: source, payload: MainFileBatchActionRoutePayload(context: context))
    }

    private init(source: MainFileBatchActionRouteSource, payload: MainFileBatchActionRoutePayload) {
        self.source = source
        self.payload = payload
    }
}

struct BatchDeleteApplyResult: Equatable {
    var report: BatchDeleteReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

struct BatchDeleteApplyGate {
    var fileIDs: [Int64]
    var preview: BatchDeletePreviewReportSnapshot?
    var deleteMode: BatchDeleteModeSnapshot
    var disabledReason: String?
    var undoConfirmationAccepted: Bool
    var isApplying: Bool
}

enum BatchDeletePreviewState: Equatable {
    case idle
    case loading(previous: BatchDeletePreviewReportSnapshot?)
    case loaded(BatchDeletePreviewReportSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: BatchDeletePreviewReportSnapshot?)

    var report: BatchDeletePreviewReportSnapshot? {
        switch self {
        case let .loaded(report), let .loading(report?), let .failed(_, report?):
            report
        case .idle, .loading, .failed:
            nil
        }
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var failure: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping, _) = self else { return nil }
        return mapping
    }
}

enum BatchDeleteEntryPolicy {
    static func openHelp(disabledReason: String?) -> String {
        MainFileBatchEntryPolicy.openHelp(
            disabledReason: disabledReason,
            defaultHelp: L10n.string("Review deletion impact for the selected files"),
            blockedHelpSuffix: L10n.string("Review deletion impact before any files move to Trash.")
        )
    }
}

enum BatchDeleteAction {
    static func preview(
        repoPath: String,
        fileIDs: [Int64],
        deleteMode: BatchDeleteModeSnapshot,
        deleter: any CoreBatchDeleting,
        errorMapper: any CoreErrorMapping
    ) async -> BatchDeletePreviewState {
        do {
            let report = try await deleter.previewBatchDelete(
                repoPath: repoPath,
                fileIDs: fileIDs,
                deleteMode: deleteMode
            )
            return .loaded(report)
        } catch {
            return await .failed(errorMapper.mapError(error), previous: nil)
        }
    }

    static func apply(
        repoPath: String,
        fileIDs: [Int64],
        preview: BatchDeletePreviewReportSnapshot,
        deleter: any CoreBatchDeleting,
        errorMapper: any CoreErrorMapping
    ) async -> BatchDeleteApplyResult {
        do {
            let report = try await deleter.batchDeleteToTrash(
                repoPath: repoPath,
                fileIDs: fileIDs,
                deleteMode: preview.deleteMode,
                previewToken: preview.previewToken
            )
            return BatchDeleteApplyResult(report: report, failure: nil)
        } catch {
            return await BatchDeleteApplyResult(
                report: nil,
                failure: errorMapper.mapError(error)
            )
        }
    }
}

enum BatchDeleteValidation {
    static func canApply(_ gate: BatchDeleteApplyGate) -> Bool {
        let selectedFileIDs = Set(gate.fileIDs)
        guard !gate.isApplying,
              gate.disabledReason == nil,
              !selectedFileIDs.isEmpty,
              let preview = gate.preview,
              preview.canApply,
              preview.deleteMode == gate.deleteMode else { return false }
        let previewFileIDs = Set(preview.fileIDs)
        guard !previewFileIDs.isEmpty,
              previewFileIDs.isSubset(of: selectedFileIDs),
              preview.requestedFileCount == Int64(previewFileIDs.count) else { return false }
        return preview.undoAvailable || gate.undoConfirmationAccepted
    }

    static func canRetryFailed(report: BatchDeleteReportSnapshot?, isApplying: Bool) -> Bool {
        guard !isApplying, let report else { return false }
        return !failedFileIDs(report).isEmpty
    }

    static func failedFileIDs(_ report: BatchDeleteReportSnapshot) -> [Int64] {
        report.itemResults.filter { $0.status == .failed }.map(\.fileID)
    }
}

enum BatchDeleteUndoAction {
    static func stateAfterBatchApply(
        repoPath: String,
        report: BatchDeleteReportSnapshot?,
        failure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState? {
        await BatchTagUndoAction.stateAfterBatchApply(
            request: BatchUndoStateRequest(
                repoPath: repoPath,
                shouldRefreshConsumer: report?.shouldRefreshConsumerAfterApply == true,
                undoToken: report?.undoToken,
                failure: failure,
                unavailableResultReason: L10n.string("Undo is unavailable for this deletion result.")
            ),
            undoStore: undoStore,
            errorMapper: errorMapper
        )
    }
}

extension BatchDeletePreviewReportSnapshot {
    var fileIDs: [Int64] {
        items.map(\.fileID)
    }

    var hasIndexRemovalCandidates: Bool {
        indexOnlyAndMissingCount > 0
    }

    var hasTrashCandidates: Bool {
        willTrashCount > 0
    }

    var indexOnlyAndMissingCount: Int64 {
        indexOnlyCount + missingCount
    }
}

extension BatchDeleteReportSnapshot {
    var successfulDeleteCount: Int64 {
        movedToTrashCount + removedFromIndexCount
    }

    var shouldRefreshConsumerAfterApply: Bool {
        successfulDeleteCount > 0 || !affectedFileIDs.isEmpty || undoToken != nil
    }

    var shouldCloseSheetAfterApply: Bool {
        failedCount == 0
    }
}

struct BatchDeletePreviewReportPresentation: Equatable {
    var trashSummaryText: LocalizedMessage
    var indexOnlySummaryText: LocalizedMessage
    var blockedSummaryText: LocalizedMessage
    var undoSummaryText: LocalizedMessage
    var safetySummaryText: LocalizedMessage

    init(report: BatchDeletePreviewReportSnapshot) {
        trashSummaryText = L10n.pluralMessage("file-actions.delete.preview.move-to-trash", count: report.willTrashCount)
        indexOnlySummaryText = L10n.pluralMessage(
            "file-actions.delete.preview.remove-from-index",
            count: report.indexOnlyCount
        )
        blockedSummaryText = L10n.pluralMessage(
            "file-actions.delete.preview.blocked-and-excluded",
            count: report.blockedCount
        )
        undoSummaryText = report.undoAvailable
            ? L10n.message("Undo: available after completion")
            : L10n.message("Undo: unavailable")
        safetySummaryText = L10n.message("No files will be permanently deleted")
    }
}

struct BatchDeleteReportPresentation: Equatable {
    var successSummaryText: LocalizedMessage
    var skippedSummaryText: LocalizedMessage
    var failedSummaryText: LocalizedMessage
    var undoSummaryText: LocalizedMessage

    init(report: BatchDeleteReportSnapshot) {
        successSummaryText = L10n.pluralMessage(
            "file-actions.delete.result.processed",
            count: report.successfulDeleteCount
        )
        skippedSummaryText = L10n.pluralMessage("file-actions.delete.result.skipped", count: report.skippedCount)
        failedSummaryText = L10n.pluralMessage("file-actions.delete.result.failed", count: report.failedCount)
        undoSummaryText = report.undoToken == nil
            ? L10n.message("Undo action unavailable")
            : L10n.message("Undo action recorded")
    }
}
