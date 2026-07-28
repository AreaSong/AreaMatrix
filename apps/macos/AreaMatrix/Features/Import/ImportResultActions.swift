import Foundation

extension OnboardingModel {
    @MainActor
    func showImportResult(from state: ImportProgressRouteState) {
        toastMessage = nil
        route = .importResult(ImportResultRouteState(
            sourceOpening: state.sourceOpening,
            progressState: state
        ))
    }

    @MainActor
    func finishImportResult() {
        guard case let .importResult(state) = route else { return }
        if state.shouldClearInterruptedSessionOnDone {
            Task {
                await importBatchSessionStore.clearSession(repoPath: state.sourceOpening.config.repoPath)
            }
        }
        route = Self.mainRoute(for: state.sourceOpening)
        toastMessage = nil
        consumeQueuedDockImportIfPossible()
    }

    @MainActor
    func loadImportResultChangeLog() async {
        guard case let .importResult(state) = route else { return }
        await loadImportResultChangeLog(from: state)
    }

    @MainActor
    func retryImportResultFailedItems() async {
        guard case let .importResult(state) = route, state.canRetryFailedItems else { return }

        let retryItems = state.items.filter { $0.status == .failed && $0.retryContext?.storageMode == .copy }
        var resultState = state.replacing(isRetryingFailedItems: true)
        var progressItems = retryItems.map { retryProgressItem(for: $0, phase: .pending) }
        var completed = 0
        var failed = 0

        for index in retryItems.indices {
            let item = retryItems[index]
            guard let context = item.retryContext else { continue }

            progressItems[index] = retryProgressItem(for: item, phase: .copying)
            routeImportResultRetryProgress(
                state: state,
                progressItems: progressItems,
                completed: completed,
                failed: failed,
                currentPath: item.targetPath
            )

            let retry = await retryImportResultItem(item, context: context, state: resultState)
            resultState = retry.resultState
            progressItems[index] = retry.progressItem
            completed += retry.didImport ? 1 : 0
            failed += retry.didImport ? 0 : 1

            routeImportResultRetryProgress(
                state: state,
                progressItems: progressItems,
                completed: completed,
                failed: failed,
                currentPath: retry.progressItem.targetPath
            )
        }

        route = .importResult(resultState.replacing(isRetryingFailedItems: false))
    }

    @MainActor
    func showImportResultExistingFile(itemID: ImportResultRouteState.Item.ID) {
        guard case let .importResult(state) = route else { return }
        guard let item = state.items.first(where: { $0.id == itemID }),
              let relativePath = item.existingRelativePath else { return }

        do {
            try fileRevealer.revealFile(repoPath: state.sourceOpening.config.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = L10n.message("Existing file cannot be shown in Finder.")
        }
    }

    @MainActor
    func reviewImportResultTagSuggestions(itemID: ImportResultRouteState.Item.ID) {
        guard case let .importResult(state) = route else { return }
        guard let item = state.items.first(where: { $0.id == itemID }),
              let fileID = item.fileID,
              item.status == .imported || item.status == .sourceRetained else { return }
        pendingTagSuggestionFocus = TagSuggestionPresentationRequest(
            fileID: fileID,
            source: .importResult,
            sequence: Int(fileID)
        )
        route = Self.mainRoute(for: state.sourceOpening.focusingImportResultItem(item))
        toastMessage = nil
    }

    @MainActor
    func consumePendingTagSuggestionFocus(_ request: TagSuggestionPresentationRequest) {
        if pendingTagSuggestionFocus == request {
            pendingTagSuggestionFocus = nil
        }
    }

    @MainActor
    func requestImportResultExportPrivacyConfirmation() {
        guard case let .importResult(state) = route else { return }
        route = .importResult(state.replacing(exportState: .confirmingPrivacy))
    }

    @MainActor
    func cancelImportResultExport() {
        guard case let .importResult(state) = route else { return }
        guard case .confirmingPrivacy = state.exportState else { return }
        route = .importResult(state.replacing(exportState: .idle))
    }

    @MainActor
    func exportImportResultDetails() {
        guard case let .importResult(state) = route else { return }

        do {
            let exportedPath = try importResultExporter.exportDetails(
                state.exportDetailsText,
                suggestedFilename: "AreaMatrix-Import-Result.txt"
            )
            route = .importResult(state.replacing(exportState: .exported(exportedPath)))
            toastMessage = L10n.message("Import result details exported.")
        } catch ImportResultExportError.cancelled {
            route = .importResult(state.replacing(exportState: .idle))
        } catch {
            route = .importResult(state.replacing(exportState: .failed(L10n.message("Export details failed."))))
        }
    }

    @MainActor
    private func loadImportResultChangeLog(from state: ImportResultRouteState) async {
        route = .importResult(state.replacing(changeLog: .loading))
        do {
            let entries = try await importResultChangeLister.listChanges(
                repoPath: state.sourceOpening.config.repoPath,
                filter: .importResultRecent
            )
            guard case let .importResult(latestState) = route else { return }
            route = .importResult(latestState.replacing(changeLog: .loaded(entries)))
        } catch {
            let mapping = await importProgressMapping(for: error)
            guard case let .importResult(latestState) = route else { return }
            route = .importResult(latestState.replacing(changeLog: .failed(mapping)))
        }
    }

    @MainActor
    private func retryImportResultItem(
        _ item: ImportResultRouteState.Item,
        context: ImportProgressRetryContext,
        state: ImportResultRouteState
    ) async -> ImportResultRetryOutcome {
        let traceContext = CoreImportTraceContext.operation(
            traceID: context.traceID ?? UUID().uuidString.lowercased(),
            retryOfOperationID: context.operationID,
            actionID: "repository.import.retry.confirmed",
            componentID: "macos.import.result"
        )
        let updatedRetryContext = context.replacingTraceContext(traceContext)
        await AppLogger.shared.recordUIAction(traceContext: traceContext)
        do {
            let entry = try await retryCopiedImport(updatedRetryContext, traceContext: traceContext)
            return ImportResultRetryOutcome(
                resultState: state.markingImported(item, entry: entry),
                progressItem: retryProgressItem(
                    for: item,
                    targetPath: entry.path,
                    phase: .done,
                    importCommitState: entry.importCommitState
                ),
                didImport: true
            )
        } catch {
            let mapping = await importProgressMapping(for: error)
            return ImportResultRetryOutcome(
                resultState: state.markingFailed(
                    item,
                    message: mapping.userMessage,
                    retryContext: updatedRetryContext
                ),
                progressItem: retryProgressItem(for: item, phase: .failed, errorMessage: mapping.userMessage),
                didImport: false
            )
        }
    }

    private func retryCopiedImport(
        _ context: ImportProgressRetryContext,
        traceContext: CoreImportTraceContext
    ) async throws -> FileEntrySnapshot {
        let sourceURL = URL(fileURLWithPath: context.sourcePath)
        if let importer = importProgressImporter as? any CoreObservedFileImporting {
            return try await importer.importCopiedFile(request: CoreObservedImportRequest(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy,
                traceContext: traceContext
            ))
        }
        return try await importProgressImporter.importCopiedFile(
            repoPath: context.repoPath,
            sourceURL: sourceURL,
            overrideCategory: context.overrideCategory,
            overrideFilename: context.overrideFilename,
            duplicateStrategy: context.duplicateStrategy.coreStrategy
        )
    }

    @MainActor
    private func routeImportResultRetryProgress(
        state: ImportResultRouteState,
        progressItems: [ImportBatchProgressSnapshot.Item],
        completed: Int,
        failed: Int,
        currentPath: String
    ) {
        route = .importProgress(ImportProgressRouteState(
            sourceOpening: state.sourceOpening,
            currentPath: currentPath,
            status: .running,
            completed: completed,
            failed: failed,
            remaining: max(progressItems.count - completed - failed, 0),
            items: progressItems
        ))
    }
}

private struct ImportResultRetryOutcome {
    var resultState: ImportResultRouteState
    var progressItem: ImportBatchProgressSnapshot.Item
    var didImport: Bool
}

private func retryProgressItem(
    for item: ImportResultRouteState.Item,
    targetPath: String? = nil,
    phase: ImportBatchProgressSnapshot.Phase,
    importCommitState: CoreImportCommitState = .committed,
    errorMessage: String? = nil
) -> ImportBatchProgressSnapshot.Item {
    ImportBatchProgressSnapshot.Item(
        fileID: item.fileID,
        sourcePath: item.sourcePath,
        targetPath: targetPath ?? item.targetPath,
        phase: phase,
        importCommitState: importCommitState,
        errorMessage: errorMessage,
        existingRelativePath: item.existingRelativePath
    )
}
