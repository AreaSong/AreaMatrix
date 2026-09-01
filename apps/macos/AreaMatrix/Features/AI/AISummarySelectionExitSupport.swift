import Foundation

struct AISummarySelectionExitRequest: Identifiable, Equatable {
    let previousIDs: Set<Int64>
    let requestedIDs: Set<Int64>

    var id: String {
        "\(Self.idList(previousIDs))->\(Self.idList(requestedIDs))"
    }

    static func shouldPrompt(
        previousIDs: Set<Int64>,
        requestedIDs: Set<Int64>,
        needsConfirmation: Bool
    ) -> Bool {
        needsConfirmation && previousIDs != requestedIDs
    }

    private static func idList(_ ids: Set<Int64>) -> String {
        ids.sorted().map(String.init).joined(separator: ",")
    }
}

struct AISummarySelectionExitState: Equatable {
    private(set) var pendingRequest: AISummarySelectionExitRequest?
    private var isRestoring = false
    private var isApplying = false

    mutating func handleChange(
        previousIDs: Set<Int64>,
        requestedIDs: Set<Int64>,
        needsConfirmation: Bool
    ) -> AISummarySelectionExitAction {
        if isRestoring {
            isRestoring = false
            return .ignoreRestoredSelection
        }
        if isApplying {
            isApplying = false
            return .apply(previousIDs: previousIDs, requestedIDs: requestedIDs)
        }
        guard AISummarySelectionExitRequest.shouldPrompt(
            previousIDs: previousIDs,
            requestedIDs: requestedIDs,
            needsConfirmation: needsConfirmation
        ) else {
            return .apply(previousIDs: previousIDs, requestedIDs: requestedIDs)
        }
        let request = AISummarySelectionExitRequest(previousIDs: previousIDs, requestedIDs: requestedIDs)
        pendingRequest = request
        isRestoring = true
        return .restore(request.previousIDs)
    }

    mutating func cancelPending() -> Set<Int64>? {
        guard let request = pendingRequest else { return nil }
        pendingRequest = nil
        isRestoring = true
        return request.previousIDs
    }

    mutating func takePendingForApply() -> AISummarySelectionExitRequest? {
        guard let request = pendingRequest else { return nil }
        pendingRequest = nil
        isApplying = true
        return request
    }

    mutating func finishDirectApply() {
        isApplying = false
    }

    mutating func cancelRestoreFlag() {
        isRestoring = false
    }
}

enum AISummarySelectionExitAction: Equatable {
    case apply(previousIDs: Set<Int64>, requestedIDs: Set<Int64>)
    case restore(Set<Int64>)
    case ignoreRestoredSelection
}

extension MainRepositoryContentView {
    func handleSelectedFileIDsChange(previousIDs: Set<Int64>, ids: Set<Int64>) {
        let action = summaryExitController.selectionExitState.handleChange(
            previousIDs: previousIDs,
            requestedIDs: ids,
            needsConfirmation: summaryExitController.needsConfirmation
        )
        performSummarySelectionExitAction(action)
    }

    func cancelPendingSummarySelectionExit() {
        guard let ids = summaryExitController.selectionExitState.cancelPending() else { return }
        restoreSelectedFileIDs(ids)
    }

    func saveAndFinishPendingSummarySelectionExit() async {
        guard await summaryExitController.saveChanges() else { return }
        finishPendingSummarySelectionExit()
    }

    func finishPendingSummarySelectionExit() {
        guard let request = summaryExitController.selectionExitState.takePendingForApply() else { return }
        applyPendingSummarySelectionExit(request)
    }

    private func performSummarySelectionExitAction(_ action: AISummarySelectionExitAction) {
        switch action {
        case let .apply(previousIDs, requestedIDs):
            applySelectedFileIDs(requestedIDs, leaving: previousIDs)
        case let .restore(ids):
            restoreSelectedFileIDs(ids)
        case .ignoreRestoredSelection:
            break
        }
    }

    private func applySelectedFileIDs(_ ids: Set<Int64>, leaving previousIDs: Set<Int64>) {
        MainRepositoryNoteDraftRouting.showFailedDraftBannerIfNeeded(
            leaving: previousIDs,
            noteModel: detailNoteModel,
            listModel: fileListModel
        )
        if !ids.isEmpty {
            importProgressSelectionState.selectedIDs = []
        }
        Task {
            await fileListModel.selectFiles(ids)
        }
    }

    private func applyPendingSummarySelectionExit(_ request: AISummarySelectionExitRequest) {
        if selectionModel.fileIDs == request.requestedIDs {
            summaryExitController.selectionExitState.finishDirectApply()
            applySelectedFileIDs(request.requestedIDs, leaving: request.previousIDs)
            return
        }
        selectionModel.fileIDs = request.requestedIDs
    }

    private func restoreSelectedFileIDs(_ ids: Set<Int64>) {
        if !ids.isEmpty {
            importProgressSelectionState.selectedIDs = []
        }
        guard selectionModel.fileIDs != ids else {
            summaryExitController.selectionExitState.cancelRestoreFlag()
            return
        }
        selectionModel.fileIDs = ids
    }
}
