import Foundation

enum BatchAddTagsRouteSource: String, Equatable {
    case detailMulti
    case listContextMenu
    case commandPalette
}

struct BatchAddTagsRoute: Identifiable, Equatable {
    let source: BatchAddTagsRouteSource
    let fileIDs: [Int64]
    let selectedCount: Int
    let disabledReason: String?

    var id: String {
        "\(source.rawValue):\(fileIDs.map(String.init).joined(separator: ",")):\(selectedCount):\(disabledReason ?? "")"
    }
}

struct MainRepositoryDetailPaneTagActions {
    let onLoadTags: () -> Void
    let onRetryTags: () -> Void
    let onAddTag: (String) -> Void
    let onRemoveTag: (String) -> Void
    let onUndoTagChange: () -> Void
    let onDismissTagUndoToast: () -> Void
    let onBatchTagUndoStateChange: (BatchTagUndoState) -> Void
}

struct MultiSelectionDetailRefreshResult: Equatable {
    var files: [FileEntrySnapshot]
    var errorMapping: CoreErrorMappingSnapshot?
}

struct BatchMutationReportPresentation: Equatable {
    let addedSummaryText: String
    let skippedSummaryText: String
    let failedSummaryText: String

    init(report: BatchMutationReportSnapshot) {
        let added = BatchMutationReportSummary(status: .added, relationCount: report.addedCount, report: report)
        let skipped = BatchMutationReportSummary(
            status: .alreadyHadTag,
            relationCount: report.skippedCount,
            report: report
        )
        let failed = BatchMutationReportSummary(status: .failed, relationCount: report.failedCount, report: report)
        addedSummaryText = added.addedText
        skippedSummaryText = skipped.skippedText
        failedSummaryText = failed.failedText
    }
}

enum BatchTagUndoState: Equatable {
    case idle
    case loading(token: String)
    case ready(UndoActionRecordSnapshot)
    case disabled(UndoActionRecordSnapshot, reason: String)
    case unavailable(reason: String)
    case undoing(UndoActionRecordSnapshot)
    case undone(UndoActionResultSnapshot)
    case failed(CoreErrorMappingSnapshot, previous: UndoActionRecordSnapshot?)

    var action: UndoActionRecordSnapshot? {
        switch self {
        case let .ready(action), let .disabled(action, _), let .undoing(action), let .failed(_, action?):
            action
        case .idle, .loading, .unavailable, .undone, .failed:
            nil
        }
    }

    var executableAction: UndoActionRecordSnapshot? {
        guard case let .ready(action) = self else { return nil }
        return action
    }

    var isBusy: Bool {
        switch self {
        case .loading, .undoing:
            true
        case .idle, .ready, .disabled, .unavailable, .undone, .failed:
            false
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

struct BatchTagUndoLoadResult: Equatable {
    var action: UndoActionRecordSnapshot?
    var unavailableReason: String?
    var failure: CoreErrorMappingSnapshot?

    var toastState: BatchTagUndoState? {
        if let failure { return .failed(failure, previous: action) }
        if let action, let unavailableReason { return .disabled(action, reason: unavailableReason) }
        if let unavailableReason { return .unavailable(reason: unavailableReason) }
        if let action { return .ready(action) }
        return nil
    }
}

struct BatchTagUndoApplyResult: Equatable {
    var result: UndoActionResultSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

struct BatchTagUndoActionLogRefreshResult: Equatable {
    var action: UndoActionRecordSnapshot?
    var failure: CoreErrorMappingSnapshot?
}

struct BatchAddTagsSheetCompletion: Equatable {
    var undoState: BatchTagUndoState?
    var closesSheet: Bool
}

struct BatchTagUndoRefreshPlan: Equatable {
    var refreshTargets: [String]

    var refreshesCurrentList: Bool {
        containsAny(["files", "tree"])
    }

    var refreshesSelectionDetails: Bool {
        containsAny(["files", "tags", "selection"])
    }

    var refreshesChangeLog: Bool {
        contains("change_log")
    }

    var refreshesUndoActions: Bool {
        contains("undo_actions")
    }

    private func containsAny(_ targets: [String]) -> Bool {
        targets.contains { contains($0) }
    }

    private func contains(_ target: String) -> Bool {
        refreshTargets.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
    }
}

enum BatchTagUndoAction {
    static func refreshLatestToastState(
        repoPath: String,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoState {
        let loadResult = await loadLatestAction(
            repoPath: repoPath,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        return loadResult.toastState ?? .idle
    }

    static func completionAfterBatchApply(
        repoPath: String,
        report: BatchMutationReportSnapshot?,
        failure: CoreErrorMappingSnapshot?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchAddTagsSheetCompletion {
        guard failure == nil, let report, report.failedCount == 0 else {
            return BatchAddTagsSheetCompletion(undoState: nil, closesSheet: false)
        }
        guard let token = normalizedToken(report.undoToken) else {
            return BatchAddTagsSheetCompletion(
                undoState: .unavailable(reason: "Undo is unavailable for this result."),
                closesSheet: true
            )
        }

        let loadResult = await loadAction(
            repoPath: repoPath,
            undoToken: token,
            undoStore: undoStore,
            errorMapper: errorMapper
        )
        if let toastState = loadResult.toastState {
            return BatchAddTagsSheetCompletion(undoState: toastState, closesSheet: true)
        }
        return BatchAddTagsSheetCompletion(
            undoState: .unavailable(reason: "Undo action is no longer available."),
            closesSheet: true
        )
    }

    static func loadAction(
        repoPath: String,
        undoToken: String?,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoLoadResult {
        guard let token = normalizedToken(undoToken) else {
            return BatchTagUndoLoadResult(action: nil, unavailableReason: "Undo is unavailable for this result.", failure: nil)
        }
        do {
            let actions = try await undoStore.listUndoActions(repoPath: repoPath)
            guard let action = actions.first(where: { $0.actionID == token }) else {
                return BatchTagUndoLoadResult(action: nil, unavailableReason: "Undo action is no longer available.", failure: nil)
            }
            return loadResult(for: action)
        } catch {
            return BatchTagUndoLoadResult(
                action: nil,
                unavailableReason: nil,
                failure: await mapError(error, errorMapper: errorMapper)
            )
        }
    }

    static func loadLatestAction(
        repoPath: String,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoLoadResult {
        do {
            let actions = try await undoStore.listUndoActions(repoPath: repoPath)
            guard let action = latestToastAction(from: actions) else {
                return BatchTagUndoLoadResult(action: nil, unavailableReason: nil, failure: nil)
            }
            return loadResult(for: action)
        } catch {
            return BatchTagUndoLoadResult(
                action: nil,
                unavailableReason: nil,
                failure: await mapError(error, errorMapper: errorMapper)
            )
        }
    }

    static func undo(
        repoPath: String,
        action: UndoActionRecordSnapshot,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoApplyResult {
        do {
            let result = try await undoStore.undoAction(repoPath: repoPath, actionID: action.actionID)
            return BatchTagUndoApplyResult(result: result, failure: nil)
        } catch {
            return BatchTagUndoApplyResult(result: nil, failure: await mapError(error, errorMapper: errorMapper))
        }
    }

    static func refreshActionLog(
        repoPath: String,
        actionID: String,
        undoStore: any CoreUndoActionLogging,
        errorMapper: any CoreErrorMapping
    ) async -> BatchTagUndoActionLogRefreshResult {
        do {
            let actions = try await undoStore.listUndoActions(repoPath: repoPath)
            return BatchTagUndoActionLogRefreshResult(
                action: actions.first { $0.actionID == actionID },
                failure: nil
            )
        } catch {
            return BatchTagUndoActionLogRefreshResult(
                action: nil,
                failure: await mapError(error, errorMapper: errorMapper)
            )
        }
    }

    private static func normalizedToken(_ undoToken: String?) -> String? {
        let token = undoToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return token.isEmpty ? nil : token
    }

    private static func latestToastAction(from actions: [UndoActionRecordSnapshot]) -> UndoActionRecordSnapshot? {
        actions.first { action in
            action.status == .pending || action.status == .blocked || action.status == .expired
        }
    }

    private static func loadResult(for action: UndoActionRecordSnapshot) -> BatchTagUndoLoadResult {
        guard action.status == .pending, action.canUndo else {
            return BatchTagUndoLoadResult(
                action: action,
                unavailableReason: disabledReason(for: action),
                failure: nil
            )
        }
        return BatchTagUndoLoadResult(action: action, unavailableReason: nil, failure: nil)
    }

    private static func disabledReason(for action: UndoActionRecordSnapshot) -> String {
        if let reason = action.disabledReason, !reason.isEmpty { return reason }
        switch action.status {
        case .blocked:
            return "Undo action is currently blocked."
        case .expired:
            return "Undo action expired."
        case .executed:
            return "Undo action has already been executed."
        case .pending:
            return "Undo action is currently unavailable."
        }
    }

    private static func mapError(_ error: Error, errorMapper: any CoreErrorMapping) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError { return await errorMapper.mapCoreError(coreError) }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

private struct BatchMutationReportSummary {
    var status: BatchMutationStatusSnapshot
    var relationCount: Int64
    var report: BatchMutationReportSnapshot

    var addedText: String {
        guard fileCount > 0 else { return relationOnlyText(action: "added", emptyText: "Added to 0 files") }
        return "Added to \(Self.countText(fileCount, singular: "file", plural: "files"))\(relationSuffix)"
    }

    var skippedText: String {
        guard fileCount > 0 else {
            return relationOnlyText(action: "already existed", emptyText: "0 files already had these tags")
        }
        return "\(Self.countText(fileCount, singular: "file", plural: "files")) already had these tags\(relationSuffix)"
    }

    var failedText: String {
        guard fileCount > 0 else { return relationOnlyText(action: "failed", emptyText: "0 failed") }
        return "\(Self.countText(fileCount, singular: "file", plural: "files")) failed\(relationSuffix)"
    }

    private var fileCount: Int64 {
        Int64(Set(report.itemResults.filter { $0.status == status }.map(\.fileID)).count)
    }

    private var relationSuffix: String {
        guard relationCount > 0, relationCount != fileCount else { return "" }
        return " (\(Self.countText(relationCount, singular: "tag relation", plural: "tag relations")))"
    }

    private func relationOnlyText(action: String, emptyText: String) -> String {
        guard relationCount > 0 else { return emptyText }
        return "\(Self.countText(relationCount, singular: "tag relation", plural: "tag relations")) \(action)"
    }

    private static func countText(_ count: Int64, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}

struct MultiSelectionDetailRefreshRequest {
    var ids: Set<Int64>
    var repoPath: String
    var currentFiles: [FileEntrySnapshot]
    var detailer: any CoreFileDetailing
    var errorMapper: any CoreErrorMapping
}

enum MultiSelectionDetailLoader {
    static func refresh(
        request: MultiSelectionDetailRefreshRequest,
        shouldContinue: @escaping @MainActor () -> Bool
    ) async -> MultiSelectionDetailRefreshResult? {
        var refreshedFiles: [FileEntrySnapshot] = []
        var firstFailure: CoreErrorMappingSnapshot?

        for id in request.ids.sorted() {
            do {
                let loadedFile = try await request.detailer.getFile(repoPath: request.repoPath, fileID: id)
                guard await shouldContinue() else { return nil }
                if request.ids.contains(loadedFile.id) {
                    refreshedFiles.append(loadedFile)
                }
            } catch {
                let mappedError = await mapCoreError(error, errorMapper: request.errorMapper)
                guard await shouldContinue() else { return nil }
                firstFailure = firstFailure ?? mappedError
            }
        }

        return MultiSelectionDetailRefreshResult(
            files: mergedFiles(replacing: request.currentFiles, with: refreshedFiles),
            errorMapping: firstFailure
        )
    }

    private static func mergedFiles(
        replacing currentFiles: [FileEntrySnapshot],
        with refreshedFiles: [FileEntrySnapshot]
    ) -> [FileEntrySnapshot] {
        var refreshedByID = Dictionary(uniqueKeysWithValues: refreshedFiles.map { ($0.id, $0) })
        let existingFiles = currentFiles.map { file in
            refreshedByID.removeValue(forKey: file.id) ?? file
        }
        return existingFiles + refreshedByID.values.sorted { $0.currentName < $1.currentName }
    }

    private static func mapCoreError(
        _ error: Error,
        errorMapper: any CoreErrorMapping
    ) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

extension MainFileListModel {
    var currentCategoryDisplayName: String {
        guard let currentCategory, !currentCategory.isEmpty else { return "files" }
        return currentCategory
    }

    func cachedFile(id: Int64) -> FileEntrySnapshot? {
        files.first { $0.id == id }
    }

    func selectedFileIDForExternalRemoval(path: String) -> Int64? {
        if let selectedFileDetail, selectedFileDetail.path == path {
            return selectedFileDetail.id
        }
        return files.first { $0.path == path }?.id
    }

    func missingDetailSnapshotIfNeeded(_ error: Error, fileID: Int64) -> FileEntrySnapshot? {
        guard case let .FileNotFound(path) = error as? CoreError else { return nil }
        return missingSnapshot(fileID: fileID, fallbackPath: path)
    }

    func missingSnapshot(fileID: Int64, fallbackPath: String) -> FileEntrySnapshot? {
        var snapshot = selectedFileDetail ??
            files.first { $0.id == fileID } ??
            cachedFile(id: fileID)
        snapshot?.availability = .missing
        if snapshot == nil, fallbackPath == "\(fileID)" || fallbackPath.isEmpty {
            return nil
        }
        return snapshot
    }

    func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    func validateExternalSyncResult(
        _ result: SyncResultSnapshot,
        event: MainExternalCreatedFileEvent
    ) throws {
        guard result.errors.isEmpty else {
            throw CoreError.Internal(
                message: """
                \(event.kind.displayName) event \(event.fsEventID) returned sync errors: \(result.errors
                    .joined(separator: "; "))
                """
            )
        }
    }
}

extension CoreErrorMappingSnapshot {
    static func missingFromExternalChange(fileID: Int64) -> CoreErrorMappingSnapshot {
        CoreErrorMappingSnapshot(
            kind: .fileNotFound,
            userMessage: "The selected file is missing.",
            severity: .medium,
            suggestedAction: "Refresh the current list or remove the stale index entry.",
            recoverability: .refreshRequired,
            rawContext: "file_id=\(fileID)"
        )
    }
}
