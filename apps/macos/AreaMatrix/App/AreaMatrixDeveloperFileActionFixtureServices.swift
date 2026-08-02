import Foundation

#if DEBUG
actor DeveloperFileActionCoreFixture: CoreTagCRUD, CoreUndoActionLogging, CoreRedoActionLogging {
    private var tagSet = DeveloperFileActionScenarioFixture.tagSet
    private var undoActions = DeveloperFileActionScenarioFixture.undoActions
    private var redoActions = DeveloperFileActionScenarioFixture.redoActions

    func listTags(repoPath _: String, fileID: Int64) async throws -> TagSetSnapshot {
        tagSetForFile(fileID)
    }

    func addTag(repoPath _: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty, !tagSet.fileTags.contains(where: { $0.value == normalized }) {
            let record = tagRecord(value: normalized, selected: true)
            tagSet.fileTags.append(record)
            upsertAvailableTag(record)
        }
        return tagSetForFile(fileID)
    }

    func removeTag(repoPath _: String, fileID: Int64, tag: String) async throws -> TagSetSnapshot {
        tagSet.fileTags.removeAll { $0.value == tag }
        tagSet.availableTags = tagSet.availableTags.map { record in
            guard record.value == tag else { return record }
            var updated = record
            updated.selected = false
            return updated
        }
        return tagSetForFile(fileID)
    }

    func batchAddTags(
        repoPath _: String,
        fileIDs: [Int64],
        tags: [String]
    ) async throws -> BatchMutationReportSnapshot {
        let results = fileIDs.flatMap { fileID in
            tags.map { tag in
                BatchMutationItemResultSnapshot(fileID: fileID, tag: tag, status: .added, error: nil)
            }
        }
        recordUndo(
            kind: "batch_add_tags",
            summary: "Added \(tags.count) tags to \(fileIDs.count) files.",
            fileIDs: fileIDs,
            token: "developer-undo-batch-tags"
        )
        return BatchMutationReportSnapshot(
            requestedFileCount: Int64(fileIDs.count),
            requestedTagCount: Int64(tags.count),
            addedCount: Int64(results.count),
            skippedCount: 0,
            failedCount: 0,
            itemResults: results,
            undoToken: "developer-undo-batch-tags"
        )
    }

    func suggestTagsForFile(
        repoPath _: String,
        request: TagSuggestionRequestSnapshot
    ) async throws -> TagSuggestionReportSnapshot {
        var report = DeveloperFileActionScenarioFixture.tagSuggestionReport
        report.fileID = request.fileID
        report.tagSet = tagSetForFile(request.fileID)
        return report
    }

    func applyTagSuggestions(
        repoPath _: String,
        request: ApplyTagSuggestionsRequestSnapshot
    ) async throws -> TagSuggestionApplyReportSnapshot {
        let results = request.suggestions.map { suggestion in
            TagSuggestionApplyItemResultSnapshot(
                suggestionID: suggestion.suggestionID,
                slug: suggestion.slug,
                status: .applied,
                error: nil
            )
        }
        for suggestion in request.suggestions {
            applyTag(suggestion.slug)
        }
        return TagSuggestionApplyReportSnapshot(
            fileID: request.fileID,
            requestedCount: Int64(results.count),
            appliedCount: Int64(results.count),
            skippedCount: 0,
            failedCount: 0,
            itemResults: results,
            tagSet: tagSetForFile(request.fileID),
            undoToken: "developer-undo-tag-suggestions",
            refreshTargets: ["files", "tags", "undo_actions"]
        )
    }

    func listUndoActions(repoPath _: String) async throws -> [UndoActionRecordSnapshot] {
        undoActions
    }

    func undoAction(repoPath _: String, actionID: String) async throws -> UndoActionResultSnapshot {
        guard let index = undoActions.firstIndex(where: { $0.actionID == actionID }) else {
            throw AppSemanticError.internalFailure(rawContext: "Developer undo action not found")
        }
        let action = undoActions[index]
        undoActions[index].status = .executed
        undoActions[index].canUndo = false
        redoActions.insert(makeRedoRecord(for: action), at: 0)
        return UndoActionResultSnapshot(
            actionID: actionID,
            status: .executed,
            summary: DeveloperFileActionScenarioFixture.technicalDetail("Undone: \(action.summary)"),
            affectedCount: action.affectedCount,
            refreshTargets: ["files", "tags", "undo_actions", "redo_actions"],
            completedAt: DeveloperFileActionScenarioFixture.timestamp + 1
        )
    }

    func listRedoActions(repoPath _: String) async throws -> [RedoActionRecordSnapshot] {
        redoActions
    }

    func redoAction(repoPath _: String, actionID: String) async throws -> RedoActionResultSnapshot {
        guard let index = redoActions.firstIndex(where: { $0.actionID == actionID }) else {
            throw AppSemanticError.internalFailure(rawContext: "Developer redo action not found")
        }
        let action = redoActions[index]
        redoActions[index].status = .executed
        redoActions[index].canRedo = false
        let undoToken = "developer-undo-after-\(actionID)"
        recordUndo(kind: action.kind, summary: action.summary, fileIDs: [], token: undoToken)
        return RedoActionResultSnapshot(
            actionID: actionID,
            status: .executed,
            summary: DeveloperFileActionScenarioFixture.technicalDetail("Redone: \(action.summary)"),
            affectedCount: action.affectedCount,
            refreshTargets: ["files", "undo_actions", "redo_actions"],
            undoToken: undoToken,
            completedAt: DeveloperFileActionScenarioFixture.timestamp + 2
        )
    }

    func recordUndo(
        kind: String,
        summary: String,
        fileIDs: [Int64],
        token: String
    ) {
        let names = fileIDs.map { DeveloperFileActionScenarioFixture.file(id: $0).currentName }
        undoActions.removeAll { $0.actionID == token }
        undoActions.insert(UndoActionRecordSnapshot(
            actionID: token,
            kind: kind,
            summary: DeveloperFileActionScenarioFixture.technicalDetail(summary),
            affectedCount: Int64(fileIDs.count),
            affectedFileNames: names,
            status: .pending,
            canUndo: true,
            disabledReason: nil,
            createdAt: DeveloperFileActionScenarioFixture.timestamp,
            updatedAt: DeveloperFileActionScenarioFixture.timestamp
        ), at: 0)
    }

    private func tagSetForFile(_ fileID: Int64) -> TagSetSnapshot {
        var snapshot = tagSet
        snapshot.fileID = fileID
        return snapshot
    }

    private func applyTag(_ tag: String) {
        guard !tagSet.fileTags.contains(where: { $0.value == tag }) else { return }
        let record = tagRecord(value: tag, selected: true)
        tagSet.fileTags.append(record)
        upsertAvailableTag(record)
    }

    private func tagRecord(value: String, selected: Bool) -> TagRecordSnapshot {
        TagRecordSnapshot(
            value: value,
            label: DeveloperFileActionScenarioFixture.userContent(value),
            fileCount: selected ? 1 : 0,
            selected: selected,
            disabled: false,
            updatedAt: DeveloperFileActionScenarioFixture.timestamp
        )
    }

    private func upsertAvailableTag(_ record: TagRecordSnapshot) {
        tagSet.availableTags.removeAll { $0.value == record.value }
        tagSet.availableTags.append(record)
        tagSet.recentTags.removeAll { $0.value == record.value }
        tagSet.recentTags.insert(record, at: 0)
    }

    private func makeRedoRecord(for action: UndoActionRecordSnapshot) -> RedoActionRecordSnapshot {
        RedoActionRecordSnapshot(
            actionID: "developer-redo-\(action.actionID)",
            kind: action.kind,
            summary: action.summary,
            affectedCount: action.affectedCount,
            affectedFileNames: action.affectedFileNames,
            status: .available,
            canRedo: true,
            disabledReason: nil,
            sourceUndoActionID: action.actionID,
            createdAt: DeveloperFileActionScenarioFixture.timestamp + 1,
            updatedAt: DeveloperFileActionScenarioFixture.timestamp + 1
        )
    }
}
#endif
