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
            defaultHelp: "Review deletion impact for the selected files",
            blockedHelpSuffix: "Review deletion impact before any files move to Trash."
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
        guard failure == nil, let report, report.shouldRefreshConsumerAfterApply else { return nil }
        guard let token = normalizedToken(report.undoToken) else {
            return .unavailable(reason: "Undo is unavailable for this deletion result.")
        }

        let loadResult = await BatchTagUndoAction.loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .unavailable(reason: "Undo action is no longer available.")
    }

    private static func normalizedToken(_ undoToken: String?) -> String? {
        let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
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
    var trashSummaryText: String
    var indexOnlySummaryText: String
    var blockedSummaryText: String
    var undoSummaryText: String
    var safetySummaryText: String

    init(report: BatchDeletePreviewReportSnapshot) {
        trashSummaryText = "\(Self.itemText(report.willTrashCount)) will move to Trash"
        indexOnlySummaryText = "\(Self.itemText(report.indexOnlyCount)) can be removed from the index"
        blockedSummaryText = "\(Self.itemText(report.blockedCount)) blocked and excluded"
        undoSummaryText = report.undoAvailable ? "Undo: available after completion" : "Undo: unavailable"
        safetySummaryText = "No files will be permanently deleted"
    }

    private static func itemText(_ count: Int64) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

struct BatchDeleteReportPresentation: Equatable {
    var successSummaryText: String
    var skippedSummaryText: String
    var failedSummaryText: String
    var undoSummaryText: String

    init(report: BatchDeleteReportSnapshot) {
        successSummaryText = "\(Self.itemText(report.successfulDeleteCount)) processed"
        skippedSummaryText = "\(Self.itemText(report.skippedCount)) skipped"
        failedSummaryText = "\(Self.itemText(report.failedCount)) failed"
        undoSummaryText = report.undoToken == nil ? "Undo action unavailable" : "Undo action recorded"
    }

    private static func itemText(_ count: Int64) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}
