import Foundation

extension OnboardingModel {
    @MainActor
    func retryCurrentImportProgressItem() async {
        guard case let .importProgress(state) = route else { return }
        guard state.canRetryCurrentItem, let context = state.retryContext else { return }

        route = .importProgress(state.withRecoveryCheck(.checking))
        do {
            let entry = try await importCurrentProgressItem(context)
            await finishRetriedImportProgressItem(entry, from: state)
        } catch {
            await failRetriedImportProgressItem(error, context: context)
        }
    }

    @MainActor
    func stopImportProgressAfterCurrentFile() {
        guard case let .importProgress(state) = route else { return }
        importProgressControlState.requestStopAfterCurrentFile()
        route = .importProgress(state.withStopState(.stopping))
    }

    @MainActor
    func viewImportProgressDetails() {
        guard case let .importProgress(state) = route else { return }
        showImportResult(from: state)
    }

    @MainActor
    func stopImportProgressAndViewResults() {
        guard case let .importProgress(state) = route else { return }
        importProgressControlState.clearQueueContinuation()
        showImportResult(from: state)
    }

    @MainActor
    func requestImportProgressDiagnosticsPrivacyConfirmation() {
        guard case let .importProgress(state) = route, state.isFailed else { return }
        route = .importProgress(state.withDiagnostics(.confirmingPrivacy))
    }

    @MainActor
    func cancelImportProgressDiagnosticsPrivacyConfirmation() {
        guard case let .importProgress(state) = route else { return }
        guard case .confirmingPrivacy = state.diagnostics else { return }
        route = .importProgress(state.withDiagnostics(.idle))
    }

    @MainActor
    func collectImportProgressDiagnostics() async {
        guard case let .importProgress(state) = route else { return }
        guard case .confirmingPrivacy = state.diagnostics else { return }

        route = .importProgress(state.withDiagnostics(.collecting))
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: state.repoPath)
            guard case let .importProgress(latestState) = route else { return }
            route = .importProgress(latestState.withDiagnostics(.collected(snapshot)))
        } catch {
            guard case let .importProgress(latestState) = route else { return }
            route = await .importProgress(latestState.withDiagnostics(.failed(importProgressMapping(for: error))))
        }
    }

    @MainActor
    func openImportProgressRepositoryInFinder() {
        guard case let .importProgress(state) = route else { return }
        do {
            try finderOpener.openRepositoryInFinder(repoPath: state.repoPath)
            toastMessage = nil
        } catch {
            toastMessage = "Repository folder cannot be revealed."
        }
    }

    @MainActor
    func checkImportProgressRecoveryIfNeeded() async {
        guard case let .importProgress(state) = route else { return }
        guard case .checking = state.recoveryCheck else { return }
        guard let context = state.retryContext else { return }

        do {
            let report = try await startupRecoverer.recoverOnStartup(repoPath: context.repoPath)
            guard case let .importProgress(latestState) = route else { return }
            route = .importProgress(latestState
                .withRecoveryCheck(.retryAllowed(report.hasVisibleDetails ? report : nil)))
        } catch {
            let mapping = await importProgressMapping(for: error)
            guard case let .importProgress(latestState) = route else { return }
            route = .importProgress(latestState.withRecoveryCheck(.retryBlocked(mapping.userMessage, nil)))
        }
    }

    private func importCurrentProgressItem(_ context: ImportProgressRetryContext) async throws -> FileEntrySnapshot {
        let sourceURL = URL(fileURLWithPath: context.sourcePath)
        switch context.storageMode {
        case .copy:
            return try await importProgressImporter.importCopiedFile(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy
            )
        case .move:
            return try await importProgressImporter.importMovedFile(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy
            )
        case .indexOnly:
            return try await importProgressImporter.importIndexedFile(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy
            )
        }
    }

    @MainActor
    private func finishRetriedImportProgressItem(
        _ entry: FileEntrySnapshot,
        from state: ImportProgressRouteState
    ) async {
        guard let context = state.retryContext else { return }
        if let continuation = importProgressControlState.queueContinuation {
            await continueQueueAfterRetriedImport(
                continuation,
                context: context,
                entry: entry,
                fallbackState: state
            )
            return
        }
        finishStandaloneRetriedImport(entry, from: state)
    }

    @MainActor
    private func failRetriedImportProgressItem(
        _ error: Error,
        context: ImportProgressRetryContext
    ) async {
        let mapping = await importProgressMapping(for: error)
        let failedItem = ImportBatchProgressSnapshot.Item(
            fileID: nil,
            sourcePath: context.sourcePath,
            targetPath: ImportSingleFilePreflightTarget.relativePath(
                category: context.overrideCategory,
                filename: context.overrideFilename
            ),
            phase: .failed,
            errorMessage: mapping.userMessage
        )
        failImportEntry(
            progress: ImportBatchProgressSnapshot(
                completed: 0,
                failed: 1,
                total: 1,
                remaining: 0,
                currentPath: failedItem.targetPath,
                items: [failedItem]
            ),
            mapping: mapping,
            retryContext: context
        )
    }

    private func importProgressMapping(for error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    @MainActor
    private func finishStandaloneRetriedImport(
        _ entry: FileEntrySnapshot,
        from state: ImportProgressRouteState
    ) {
        importProgressControlState.clearQueueContinuation()
        route = Self.mainRoute(for: state.sourceOpening)
        toastMessage = "已导入：\(entry.currentName)"
        accessibilityAnnouncer.announce("已导入：\(entry.currentName)")
        consumeQueuedDockImportIfPossible()
    }

    @MainActor
    private func continueQueueAfterRetriedImport(
        _ continuation: any ImportProgressQueueContinuing,
        context: ImportProgressRetryContext,
        entry: FileEntrySnapshot,
        fallbackState: ImportProgressRouteState
    ) async {
        let outcome = await continuation.continueImportProgressQueue(
            afterRetried: context,
            entry: entry,
            controlState: importProgressControlState
        ) { progress in
            self.updateImportEntryProgress(progress)
        }
        importProgressControlState.clearQueueContinuation()
        finishContinuedImportProgressOutcome(outcome, retriedEntry: entry, fallbackState: fallbackState)
    }

    @MainActor
    private func finishContinuedImportProgressOutcome(
        _ outcome: ImportBatchImportResult?,
        retriedEntry: FileEntrySnapshot,
        fallbackState: ImportProgressRouteState
    ) {
        guard let outcome else {
            finishStandaloneRetriedImport(retriedEntry, from: fallbackState)
            return
        }
        if outcome.failedCount == 0, !outcome.needsResultSummary, let importedEntry = outcome.succeededEntries.last {
            finishStandaloneRetriedImport(importedEntry, from: fallbackState)
            return
        }
        let summary = outcome.progressSnapshot(currentPath: fallbackState.currentPath)
        showImportEntryResults(summary)
    }

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
            toastMessage = "Existing file cannot be shown in Finder."
        }
    }

    @MainActor
    func reviewImportResultTagSuggestions(itemID: ImportResultRouteState.Item.ID) {
        guard case let .importResult(state) = route else { return }
        guard let item = state.items.first(where: { $0.id == itemID }),
              let fileID = item.fileID,
              item.status == .imported else { return }
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
            toastMessage = "Import result details exported."
        } catch ImportResultExportError.cancelled {
            route = .importResult(state.replacing(exportState: .idle))
        } catch {
            route = .importResult(state.replacing(exportState: .failed("Export details failed.")))
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
        do {
            let entry = try await importProgressImporter.importCopiedFile(
                repoPath: context.repoPath,
                sourceURL: URL(fileURLWithPath: context.sourcePath),
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy
            )
            return ImportResultRetryOutcome(
                resultState: state.markingImported(item, entry: entry),
                progressItem: retryProgressItem(for: item, targetPath: entry.path, phase: .done),
                didImport: true
            )
        } catch {
            let mapping = await importProgressMapping(for: error)
            return ImportResultRetryOutcome(
                resultState: state.markingFailed(item, message: mapping.userMessage),
                progressItem: retryProgressItem(for: item, phase: .failed, errorMessage: mapping.userMessage),
                didImport: false
            )
        }
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
    errorMessage: String? = nil
) -> ImportBatchProgressSnapshot.Item {
    ImportBatchProgressSnapshot.Item(
        fileID: item.fileID,
        sourcePath: item.sourcePath,
        targetPath: targetPath ?? item.targetPath,
        phase: phase,
        errorMessage: errorMessage,
        existingRelativePath: item.existingRelativePath
    )
}
