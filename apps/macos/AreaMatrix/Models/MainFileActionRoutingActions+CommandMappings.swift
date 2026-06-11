import Foundation

extension CommandPaletteSectionSnapshot {
    init(title: String, targets: [CommandTarget]) {
        self.title = title
        self.targets = targets.map(CommandTargetSnapshot.init(coreTarget:))
    }
}

extension CommandTargetGroupSnapshot {
    init(coreGroup: CommandTargetGroup) {
        switch coreGroup {
        case .commands:
            self = .commands
        case .navigation:
            self = .navigation
        case .currentSelection:
            self = .currentSelection
        case .recent:
            self = .recent
        case .smartLists:
            self = .smartLists
        case .fileCandidates:
            self = .fileCandidates
        }
    }
}

extension CommandTargetKindSnapshot {
    init(coreKind: CommandTargetKind) {
        switch coreKind {
        case .command:
            self = .command
        case .navigation:
            self = .navigation
        case .smartList:
            self = .smartList
        case .fileCandidate:
            self = .fileCandidate
        case .recentCommand:
            self = .recentCommand
        }
    }
}

extension CommandTargetActionSnapshot {
    init(coreAction: CommandTargetAction) {
        switch coreAction {
        case .navigate:
            self = .navigate
        case .openSheet:
            self = .openSheet
        case .openConfirmation:
            self = .openConfirmation
        case .runSmartList:
            self = .runSmartList
        case .focusFile:
            self = .focusFile
        case .openSearch:
            self = .openSearch
        case .lowRiskAction:
            self = .lowRiskAction
        }
    }
}

enum AITagBatchSuggestionAction {
    static func initialReview(
        files: [FileEntrySnapshot],
        reports: [Int64: AiTagSuggestionReport],
        loadFailures: [Int64: CoreErrorMappingSnapshot] = [:]
    ) -> AITagBatchSuggestionReview {
        AITagBatchSuggestionReview(
            files: files,
            reports: reports,
            selectedIDsByFileID: reports.mapValues(AITagSuggestionAction.initialSelection),
            loadFailures: loadFailures
        )
    }

    static func selectingHighConfidence(in state: AITagBatchSuggestionState) -> AITagBatchSuggestionState {
        guard var review = state.review else { return state }
        for report in review.reports.values {
            let ids = report.suggestions.compactMap {
                AITagSuggestionAction.canApply($0) && $0.confidence >= report.confidenceThreshold ?
                    $0.suggestionId : nil
            }
            review.selectedIDsByFileID[report.fileId, default: []].formUnion(ids)
        }
        return .reviewing(review)
    }

    static func toggling(
        fileID: Int64,
        suggestionID: String,
        in state: AITagBatchSuggestionState
    ) -> AITagBatchSuggestionState {
        guard var review = state.review,
              let suggestion = review.reports[fileID]?.suggestions.first(where: {
                  $0.suggestionId == suggestionID
              }) else { return state }
        var selected = review.selectedIDsByFileID[fileID, default: []]
        if selected.contains(suggestionID) {
            return rejectingSelection([suggestionID], fileID: fileID, in: state)
        } else if AITagSuggestionAction.canApply(suggestion) {
            selected.insert(suggestionID)
        }
        review.selectedIDsByFileID[fileID] = selected
        review.editSessionsByFileID[fileID] = nil
        return .reviewing(review)
    }

    static func clearingSelection(in state: AITagBatchSuggestionState) -> AITagBatchSuggestionState {
        guard var review = state.review else { return state }
        for fileID in Array(review.selectedIDsByFileID.keys) {
            guard let report = review.reports[fileID] else { continue }
            let visibleIDs = Set(report.suggestions.map(\.suggestionId))
            let idsToReject = review.selectedIDsByFileID[fileID, default: []].intersection(visibleIDs)
            guard !idsToReject.isEmpty else { continue }
            review = rejectingSelection(idsToReject, fileID: fileID, in: review)
        }
        return .reviewing(review)
    }

    static func rejectingSelection(
        _ rejectedIDs: Set<String>,
        fileID: Int64,
        in state: AITagBatchSuggestionState
    ) -> AITagBatchSuggestionState {
        guard let review = state.review else { return state }
        return .reviewing(rejectingSelection(rejectedIDs, fileID: fileID, in: review))
    }

    static func startingEdit(
        fileID: Int64,
        suggestionID: String,
        in state: AITagBatchSuggestionState,
        disabledReason: String?
    ) -> AITagBatchSuggestionState {
        guard var review = state.review, let report = review.reports[fileID] else { return state }
        review.selectedIDsByFileID[fileID, default: []].insert(suggestionID)
        let selected = review.selectedIDsByFileID[fileID] ?? []
        let singleState = AITagSuggestionState.loaded(fileID: fileID, report, selected)
        guard let session = AITagSuggestionAction.startingEdit(
            in: singleState,
            disabledReason: disabledReason
        ).editSession else { return state }
        review.editSessionsByFileID[fileID] = session
        return .reviewing(review)
    }

    static func cancelingEdit(fileID: Int64, in state: AITagBatchSuggestionState) -> AITagBatchSuggestionState {
        guard var review = state.review else { return state }
        review.editSessionsByFileID[fileID] = nil
        return .reviewing(review)
    }

    static func updatingDisplayName(
        fileID: Int64,
        suggestionID: String,
        displayName: String,
        in state: AITagBatchSuggestionState,
        disabledReason: String?
    ) -> AITagBatchSuggestionState {
        updatingEditSession(fileID: fileID, in: state, disabledReason: disabledReason) { singleState in
            AITagSuggestionAction.updatingDisplayName(
                suggestionID: suggestionID,
                displayName: displayName,
                in: singleState,
                disabledReason: disabledReason
            )
        }
    }

    static func updatingSlug(
        fileID: Int64,
        suggestionID: String,
        slug: String,
        in state: AITagBatchSuggestionState,
        disabledReason: String?
    ) -> AITagBatchSuggestionState {
        updatingEditSession(fileID: fileID, in: state, disabledReason: disabledReason) { singleState in
            AITagSuggestionAction.updatingSlug(
                suggestionID: suggestionID,
                slug: slug,
                in: singleState,
                disabledReason: disabledReason
            )
        }
    }

    static func regeneratingSlug(
        fileID: Int64,
        suggestionID: String,
        in state: AITagBatchSuggestionState,
        disabledReason: String?
    ) -> AITagBatchSuggestionState {
        updatingEditSession(fileID: fileID, in: state, disabledReason: disabledReason) { singleState in
            AITagSuggestionAction.regeneratingSlug(
                suggestionID: suggestionID,
                in: singleState,
                disabledReason: disabledReason
            )
        }
    }

    private static func updatingEditSession(
        fileID: Int64,
        in state: AITagBatchSuggestionState,
        disabledReason _: String?,
        update: (AITagSuggestionState) -> AITagSuggestionState
    ) -> AITagBatchSuggestionState {
        guard var review = state.review,
              let report = review.reports[fileID],
              let session = review.editSessionsByFileID[fileID] else { return state }
        let updated = update(.editing(fileID: fileID, report, session))
        guard let updatedSession = updated.editSession else { return state }
        review.editSessionsByFileID[fileID] = updatedSession
        return .reviewing(review)
    }

    private static func rejectingSelection(
        _ rejectedIDs: Set<String>,
        fileID: Int64,
        in review: AITagBatchSuggestionReview
    ) -> AITagBatchSuggestionReview {
        guard let report = review.reports[fileID] else { return review }
        let visibleIDs = Set(report.suggestions.map(\.suggestionId))
        let idsToReject = rejectedIDs.intersection(visibleIDs)
        guard !idsToReject.isEmpty else { return review }
        var next = review
        next.reports[fileID] = report.hidingSuggestions(idsToReject)
        next.selectedIDsByFileID[fileID, default: []].subtract(idsToReject)
        next.editSessionsByFileID[fileID] = nil
        next.rejectedFeedback.append(AITagSuggestionRejectedFeedback(
            fileID: fileID,
            rejectedIDs: idsToReject,
            callLogID: report.callLogId
        ))
        return next
    }
}
