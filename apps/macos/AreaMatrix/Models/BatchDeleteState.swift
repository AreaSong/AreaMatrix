import Foundation

enum BatchDeleteRouteSource: String, Equatable {
    case detailMulti
    case listContextMenu
    case commandPalette
}

struct BatchDeleteRoute: Identifiable, Equatable {
    let source: BatchDeleteRouteSource
    let fileIDs: [Int64]
    let selectedFiles: [FileEntrySnapshot]
    let selectedCount: Int
    let disabledReason: String?

    var id: String {
        [
            source.rawValue,
            fileIDs.map(String.init).joined(separator: ","),
            "\(selectedCount)",
            disabledReason ?? ""
        ].joined(separator: ":")
    }
}

struct BatchDeleteApplyResult: Equatable {
    var report: BatchDeleteReportSnapshot?
    var failure: CoreErrorMappingSnapshot?
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
        disabledReason.map { "\($0). Review deletion impact before any files move to Trash." } ??
            "Review deletion impact for the selected files"
    }

    static func disabledReason(
        selectedFiles: [FileEntrySnapshot],
        isReadOnly: Bool,
        isLoading: Bool,
        writeLockedFileIDs: Set<Int64>
    ) -> String? {
        if selectedFiles.isEmpty { return "No files selected" }
        if isReadOnly { return MainFileWriteActionDisabledReason.repoReadOnly.rawValue }
        if isLoading { return MainFileWriteActionDisabledReason.listLoading.rawValue }
        if selectedFiles.contains(where: { writeLockedFileIDs.contains($0.id) }) {
            return MainFileWriteActionDisabledReason.importLocked.rawValue
        }
        return nil
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
            return await .failed(mapError(error, errorMapper: errorMapper), previous: nil)
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
                failure: mapError(error, errorMapper: errorMapper)
            )
        }
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

enum BatchDeleteValidation {
    static func canApply(
        fileIDs: [Int64],
        preview: BatchDeletePreviewReportSnapshot?,
        deleteMode: BatchDeleteModeSnapshot,
        disabledReason: String?,
        undoConfirmationAccepted: Bool,
        isApplying: Bool
    ) -> Bool {
        let selectedFileIDs = Set(fileIDs)
        guard !isApplying,
              disabledReason == nil,
              !selectedFileIDs.isEmpty,
              let preview,
              preview.canApply,
              preview.deleteMode == deleteMode else { return false }
        let previewFileIDs = Set(preview.fileIDs)
        guard !previewFileIDs.isEmpty,
              previewFileIDs.isSubset(of: selectedFileIDs),
              preview.requestedFileCount == Int64(previewFileIDs.count) else { return false }
        return preview.undoAvailable || undoConfirmationAccepted
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
