import AreaMatrixCoreBridgeContract
import Foundation

#if DEBUG
enum DeveloperMainListScenarioFixture {
    static let repoPath = AreaMatrixPreviewFixtures.repositoryPath

    static var opening: RepositoryOpeningResult {
        var opening = DeveloperImportScenarioFixture.opening
        opening.currentCategoryFiles = DeveloperFileActionScenarioFixture.selectedFiles
        return opening
    }
}

actor DeveloperMainListCoreFixture: CoreRepositoryTreeListing,
    CoreFileListing,
    CoreFileDetailing,
    CoreMissingFileRecovering,
    CoreSemanticSearching,
    CoreSemanticFallbackStatusReading,
    CoreSearchFiltering,
    CoreCommandIndexing,
    CoreFileRenaming,
    CoreFileDeleting,
    CoreFileCategoryMoving,
    CoreCategoryPredicting,
    CoreChangeLogListing,
    CoreExternalChangesSyncing,
    CoreDiagnosticsCollecting,
    CoreSyncConflictDetecting {
    private var files = DeveloperFileActionScenarioFixture.selectedFiles
    private var cursor: Int64?

    func listTree(repoPath _: String, locale _: String) async throws -> RepositoryTreeNodeSnapshot {
        DeveloperMainListScenarioFixture.opening.tree
    }

    func listFiles(repoPath _: String, filter: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        let filtered = files.filter { file in
            (filter.includeDeleted != true) && (filter.category == nil || file.category == filter.category)
        }
        let start = min(Int(filter.offset), filtered.count)
        let end = min(start + Int(filter.limit), filtered.count)
        return Array(filtered[start ..< end])
    }

    func getFile(repoPath _: String, fileID: Int64) async throws -> FileEntrySnapshot {
        guard let file = files.first(where: { $0.id == fileID }) else {
            throw AppSemanticError.fileNotFound(rawContext: "developer-file-\(fileID)")
        }
        return file
    }

    func missingFileState(repoPath _: String, fileID: Int64) async throws -> MissingFileStateSnapshot {
        let file = try fixtureFile(id: fileID)
        return MissingFileStateSnapshot(
            fileID: file.id,
            relativePath: file.path,
            lastKnownPath: file.sourcePath,
            expectedHashSha256: file.hashSha256,
            reason: .pathMissing,
            canLocate: true
        )
    }

    func relinkMissingFile(
        repoPath _: String,
        fileID: Int64,
        newPath: String
    ) async throws -> MissingFileRecoveryReportSnapshot {
        MissingFileRecoveryReportSnapshot(
            fileID: fileID,
            status: .relinked,
            previousPath: files.first(where: { $0.id == fileID })?.sourcePath,
            currentPath: newPath,
            hashMatched: true,
            fileDeleted: false,
            message: nil
        )
    }

    func semanticSearch(
        repoPath _: String,
        request: SearchQueryRequestSnapshot
    ) async throws -> SearchResultPageSnapshot {
        DeveloperSearchScenarioFixture.searchPage(for: request)
    }

    func buildEmbeddingIndex(
        repoPath _: String,
        request _: SearchQueryRequestSnapshot
    ) async throws -> SemanticIndexBuildReportSnapshot {
        SemanticIndexBuildReportSnapshot(
            status: .ready,
            route: .local,
            totalCount: Int64(files.count),
            processedCount: Int64(files.count),
            skippedCount: 0,
            failedCount: 0,
            privacySkippedCount: 0,
            providerName: "AreaMatrix Local",
            callLogID: nil,
            fallbackReason: nil,
            message: nil
        )
    }

    func semanticFallbackStatus(
        repoPath _: String,
        request _: AIFallbackStatusRequestSnapshot
    ) async throws -> AIFallbackStatusSnapshot {
        AIFallbackStatusSnapshot(
            operation: .semanticSearch,
            kind: .semanticIndexNotReady,
            category: .unavailable,
            title: L10n.string("Semantic index is not ready"),
            message: L10n.string("Build the semantic index or use normal search."),
            retryable: false,
            retryDisabledReason: nil,
            primaryAction: .buildSemanticIndex,
            secondaryAction: nil,
            nonAIFallbackAction: .useNormalSearch,
            route: .local,
            callLogID: nil,
            privacyRuleID: nil,
            retryAfter: nil
        )
    }

    func listFilterFacets(
        repoPath _: String,
        request: SearchFacetRequestSnapshot
    ) async throws -> SearchFacetsSnapshot {
        SearchFacetsSnapshot(
            query: request.query,
            totalCount: Int64(files.count),
            categories: categoryCounts(request: request),
            fileKinds: [],
            tags: [],
            storageModes: [],
            dateBounds: SearchDateFacetBoundsSnapshot(
                oldestImportedAt: files.map(\.importedAt).min(),
                newestImportedAt: files.map(\.importedAt).max(),
                oldestModifiedAt: files.map(\.updatedAt).min(),
                newestModifiedAt: files.map(\.updatedAt).max()
            ),
            activeFilterCount: request.filters.activeFilterCount
        )
    }

    func listCommandTargets(
        repoPath _: String,
        context _: CommandIndexRequestSnapshot
    ) async throws -> CoreCommandIndexSnapshot {
        CoreCommandIndexSnapshot(
            commands: [],
            navigationTargets: [],
            currentSelectionTargets: [],
            recentTargets: [],
            smartLists: [],
            fileCandidates: [],
            generatedAt: DeveloperFileActionScenarioFixture.timestamp
        )
    }

    func renameFile(repoPath _: String, fileID: Int64, newName: String) async throws -> FileEntrySnapshot {
        try mutateFile(id: fileID) { file in
            file.currentName = newName
            file.path = ((file.path as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(newName)
        }
    }

    func deleteFile(repoPath _: String, fileID: Int64) async throws {
        files.removeAll { $0.id == fileID }
    }

    func removeIndexEntry(repoPath _: String, fileID: Int64) async throws {
        files.removeAll { $0.id == fileID }
    }

    func previewMoveToCategory(
        repoPath _: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> MoveToCategoryPreviewSnapshot {
        let file = try fixtureFile(id: fileID)
        return MoveToCategoryPreviewSnapshot(
            fileID: file.id,
            fromCategory: file.category,
            toCategory: newCategory,
            currentPath: file.path,
            targetPath: "\(newCategory)/\(file.currentName)",
            targetName: file.currentName,
            storageMode: file.storageMode,
            indexOnly: file.storageMode == "Indexed",
            nameConflictResolved: false,
            willMoveFile: file.storageMode != "Indexed"
        )
    }

    func moveToCategory(
        repoPath _: String,
        fileID: Int64,
        newCategory: String
    ) async throws -> FileEntrySnapshot {
        try mutateFile(id: fileID) { file in
            file.category = newCategory
            file.path = "\(newCategory)/\(file.currentName)"
        }
    }

    func correctFileCategory(
        repoPath _: String,
        fileID: Int64,
        targetCategory: String,
        moveFile: Bool,
        remember: Bool
    ) async throws -> ClassifierCorrectionResultSnapshot {
        let updated = try mutateFile(id: fileID) { file in
            file.category = targetCategory
            file.path = "\(targetCategory)/\(file.currentName)"
        }
        return ClassifierCorrectionResultSnapshot(
            updatedFile: updated,
            ruleDraft: nil,
            moveFileRequested: moveFile,
            rememberRequested: remember,
            ruleConfirmationRequired: remember
        )
    }

    func predictCategory(repoPath _: String, filename: String) async throws -> ClassifyResultSnapshot {
        DeveloperImportScenarioFixture.prediction(filename: filename)
    }

    func listChanges(repoPath _: String, filter _: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        DeveloperLibraryScenarioFixture.changeLogEntries
    }

    func syncExternalChanges(
        repoPath _: String,
        events: [MainExternalCreatedFileEvent]
    ) async throws -> SyncResultSnapshot {
        SyncResultSnapshot(
            detectedCreates: Int64(events.filter { $0.kind == .created }.count),
            detectedRenames: Int64(events.filter { $0.kind == .renamed }.count),
            detectedDeletes: Int64(events.filter { $0.kind == .removed }.count),
            detectedModifies: Int64(events.filter { $0.kind == .modified }.count),
            errors: []
        )
    }

    func getFSEventCursor(repoPath _: String) async throws -> Int64? {
        cursor
    }

    func setFSEventCursor(repoPath _: String, lastEventID: Int64) async throws {
        cursor = lastEventID
    }

    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        DeveloperOnboardingScenarioFixture.diagnostics
    }

    func detectSyncConflicts(repoPath _: String) async throws -> [SyncConflictSnapshot] {
        []
    }

    private func mutateFile(
        id: Int64,
        mutation: (inout FileEntrySnapshot) -> Void
    ) throws -> FileEntrySnapshot {
        guard let index = files.firstIndex(where: { $0.id == id }) else {
            throw AppSemanticError.fileNotFound(rawContext: "developer-file-\(id)")
        }
        mutation(&files[index])
        return files[index]
    }

    private func fixtureFile(id: Int64) throws -> FileEntrySnapshot {
        guard let file = files.first(where: { $0.id == id }) else {
            throw AppSemanticError.fileNotFound(rawContext: "developer-file-\(id)")
        }
        return file
    }

    private func categoryCounts(request: SearchFacetRequestSnapshot) -> [SearchFacetCountSnapshot] {
        Dictionary(grouping: files, by: \.category)
            .map { category, matches in
                SearchFacetCountSnapshot(
                    value: category,
                    label: category.capitalized,
                    count: Int64(matches.count),
                    selected: request.filters.category == category,
                    disabled: false
                )
            }
            .sorted { $0.value < $1.value }
    }
}

actor DeveloperMainListAITagFixture: CoreAITagSuggestionManaging {
    func suggestTagsWithAI(
        repoPath _: String,
        request _: AITagSuggestionRequestSnapshot
    ) async throws -> AITagSuggestionReportSnapshot {
        DeveloperAIScenarioFixture.tagReport
    }

    func applyAITagSuggestions(
        repoPath _: String,
        request: ApplyAITagSuggestionsRequestSnapshot
    ) async throws -> AITagSuggestionApplyReportSnapshot {
        let tag = TagRecordSnapshot(
            value: "finance",
            label: L10n.resolve(L10n.verbatim("Finance", reason: .userContent)),
            fileCount: 1,
            selected: true,
            disabled: false,
            updatedAt: DeveloperFileActionScenarioFixture.timestamp
        )
        return AITagSuggestionApplyReportSnapshot(
            fileId: request.fileId,
            requestedCount: Int64(request.suggestions.count),
            appliedCount: Int64(request.suggestions.count),
            skippedCount: 0,
            failedCount: 0,
            itemResults: request.suggestions.map {
                AITagSuggestionApplyItemResultSnapshot(
                    suggestionId: $0.suggestionId,
                    slug: $0.slug,
                    status: .applied,
                    error: nil
                )
            },
            tagSet: TagSetSnapshot(
                fileID: request.fileId,
                fileTags: [tag],
                availableTags: [tag],
                recentTags: [tag],
                updatedAt: DeveloperFileActionScenarioFixture.timestamp
            ),
            undoToken: nil,
            callLogId: nil,
            refreshTargets: ["tags"]
        )
    }
}

struct DeveloperMainListMissingFilePicker: RepositoryMissingFilePicking {
    @MainActor
    func chooseReplacementFile(lastKnownPath _: String?) -> URL? {
        nil
    }
}

struct DeveloperMainListSystemCapabilityChecker: OnboardingSystemCapabilityChecking {
    func isTrashAvailable() -> Bool {
        false
    }

    func repositoryFinderAvailability(repoPath _: String) -> Bool {
        false
    }
}

actor DeveloperMainListICloudConflictResolver: ICloudConflictResolving {
    nonisolated let iCloudConflictResolutionCapability = ICloudConflictResolutionCapability.supported

    func resolveICloudConflict(
        _ request: ICloudConflictResolutionRequest
    ) async throws -> ICloudConflictResolutionResult {
        ICloudConflictResolutionResult(
            focusFileID: request.fileID,
            conflictID: request.conflictID,
            report: nil,
            status: .resolved,
            keptPaths: [],
            trashedPaths: [],
            undoToken: nil,
            changeLogAction: nil,
            didClearConflictState: true,
            didWriteChangeLog: false
        )
    }
}
#endif
