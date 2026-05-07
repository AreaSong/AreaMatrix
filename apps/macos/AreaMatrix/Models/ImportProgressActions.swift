import Foundation

extension OnboardingModel {
    @MainActor
    func retryCurrentImportProgressItem() async {
        guard case .importProgress(let state) = route else { return }
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
        guard case .importProgress(let state) = route else { return }
        importProgressControlState.requestStopAfterCurrentFile()
        route = .importProgress(state.withStopState(.stopping))
    }

    @MainActor
    func viewImportProgressDetails() {
        guard case .importProgress(let state) = route else { return }
        showImportResult(from: state)
    }

    @MainActor
    func stopImportProgressAndViewResults() {
        guard case .importProgress(let state) = route else { return }
        importProgressControlState.clearQueueContinuation()
        showImportResult(from: state)
    }

    @MainActor
    func requestImportProgressDiagnosticsPrivacyConfirmation() {
        guard case .importProgress(let state) = route, state.isFailed else { return }
        route = .importProgress(state.withDiagnostics(.confirmingPrivacy))
    }

    @MainActor
    func cancelImportProgressDiagnosticsPrivacyConfirmation() {
        guard case .importProgress(let state) = route else { return }
        guard case .confirmingPrivacy = state.diagnostics else { return }
        route = .importProgress(state.withDiagnostics(.idle))
    }

    @MainActor
    func collectImportProgressDiagnostics() async {
        guard case .importProgress(let state) = route else { return }
        guard case .confirmingPrivacy = state.diagnostics else { return }

        route = .importProgress(state.withDiagnostics(.collecting))
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: state.repoPath)
            guard case .importProgress(let latestState) = route else { return }
            route = .importProgress(latestState.withDiagnostics(.collected(snapshot)))
        } catch {
            guard case .importProgress(let latestState) = route else { return }
            route = .importProgress(latestState.withDiagnostics(.failed(await importProgressMapping(for: error))))
        }
    }

    @MainActor
    func openImportProgressRepositoryInFinder() {
        guard case .importProgress(let state) = route else { return }
        do {
            try finderOpener.openRepositoryInFinder(repoPath: state.repoPath)
            toastMessage = nil
        } catch {
            toastMessage = "Repository folder cannot be revealed."
        }
    }

    @MainActor
    func checkImportProgressRecoveryIfNeeded() async {
        guard case .importProgress(let state) = route else { return }
        guard case .checking = state.recoveryCheck else { return }
        guard let context = state.retryContext else { return }

        do {
            let report = try await startupRecoverer.recoverOnStartup(repoPath: context.repoPath)
            guard case .importProgress(let latestState) = route else { return }
            route = .importProgress(latestState.withRecoveryCheck(.retryAllowed(report.hasVisibleDetails ? report : nil)))
        } catch {
            let mapping = await importProgressMapping(for: error)
            guard case .importProgress(let latestState) = route else { return }
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
        guard case .importResult(let state) = route else { return }
        route = Self.mainRoute(for: state.sourceOpening)
        toastMessage = nil
        consumeQueuedDockImportIfPossible()
    }

    @MainActor
    func loadImportResultChangeLog() async {
        guard case .importResult(let state) = route else { return }
        await loadImportResultChangeLog(from: state)
    }

    @MainActor
    func retryImportResultFailedItems() async {
        guard case .importResult(let state) = route, state.canRetryFailedItems else { return }
        route = .importResult(state.replacing(isRetryingFailedItems: true))
        var nextState = state
        for item in state.items where item.status == .failed {
            guard let context = item.retryContext, context.storageMode == .copy else { continue }
            nextState = await retryImportResultItem(item, context: context, state: nextState)
            route = .importResult(nextState)
        }
        route = .importResult(nextState.replacing(isRetryingFailedItems: false))
    }

    @MainActor
    private func loadImportResultChangeLog(from state: ImportResultRouteState) async {
        route = .importResult(state.replacing(changeLog: .loading))
        do {
            let entries = try await importResultChangeLister.listChanges(
                repoPath: state.sourceOpening.config.repoPath,
                filter: .importResultRecent
            )
            guard case .importResult(let latestState) = route else { return }
            route = .importResult(latestState.replacing(changeLog: .loaded(entries)))
        } catch {
            let mapping = await importProgressMapping(for: error)
            guard case .importResult(let latestState) = route else { return }
            route = .importResult(latestState.replacing(changeLog: .failed(mapping)))
        }
    }

    @MainActor
    private func retryImportResultItem(
        _ item: ImportResultRouteState.Item,
        context: ImportProgressRetryContext,
        state: ImportResultRouteState
    ) async -> ImportResultRouteState {
        do {
            let entry = try await importProgressImporter.importCopiedFile(
                repoPath: context.repoPath,
                sourceURL: URL(fileURLWithPath: context.sourcePath),
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy
            )
            return state.markingImported(item, entry: entry)
        } catch {
            let mapping = await importProgressMapping(for: error)
            return state.markingFailed(item, message: mapping.userMessage)
        }
    }
}
