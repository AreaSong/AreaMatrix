import Foundation

extension OnboardingModel {
    @MainActor
    func retryCurrentImportProgressItem() async {
        guard case let .importProgress(state) = route else { return }
        guard state.canRetryCurrentItem, let context = state.retryContext else { return }

        route = .importProgress(state.withRecoveryCheck(.checking))
        let traceContext = CoreImportTraceContext.operation(
            traceID: context.traceID ?? UUID().uuidString.lowercased(),
            retryOfOperationID: context.operationID,
            actionID: "repository.import.retry.confirmed",
            componentID: "macos.import.progress"
        )
        let retryContext = context.replacingTraceContext(traceContext)
        await AppLogger.shared.recordUIAction(traceContext: traceContext)
        do {
            let entry = try await importCurrentProgressItem(retryContext, traceContext: traceContext)
            await finishRetriedImportProgressItem(entry, from: state, context: retryContext)
        } catch {
            await failRetriedImportProgressItem(error, context: retryContext)
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
        guard case .confirmingPrivacy = state.diagnostics else {
            guard case .collecting = state.diagnostics else { return }
            importProgressDiagnosticsGeneration += 1
            route = .importProgress(state.withDiagnostics(.idle))
            return
        }
        importProgressDiagnosticsGeneration += 1
        route = .importProgress(state.withDiagnostics(.idle))
    }

    @MainActor
    func collectImportProgressDiagnostics() async {
        guard case let .importProgress(state) = route else { return }
        guard case .confirmingPrivacy = state.diagnostics else { return }

        importProgressDiagnosticsGeneration += 1
        let generation = importProgressDiagnosticsGeneration
        route = .importProgress(state.withDiagnostics(.collecting))
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: state.repoPath)
            guard importProgressDiagnosticsGeneration == generation else { return }
            guard case let .importProgress(latestState) = route else { return }
            route = .importProgress(latestState.withDiagnostics(.collected(snapshot)))
        } catch {
            guard importProgressDiagnosticsGeneration == generation else { return }
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
            toastMessage = L10n.message("Repository folder cannot be revealed.")
        }
    }

    @MainActor
    func checkImportProgressRecoveryIfNeeded() async {
        guard case let .importProgress(state) = route else { return }
        guard case .checking = state.recoveryCheck else { return }
        guard let context = state.retryContext else { return }

        do {
            let report = try await repositoryWriteCoordinator.withWriteAccess(repoPath: context.repoPath) {
                try await self.startupRecoverer.recoverOnStartup(repoPath: context.repoPath)
            }
            guard case let .importProgress(latestState) = route else { return }
            route = .importProgress(latestState
                .withRecoveryCheck(.retryAllowed(report.hasVisibleDetails ? report : nil)))
        } catch {
            let mapping = await importProgressMapping(for: error)
            guard case let .importProgress(latestState) = route else { return }
            route = .importProgress(latestState.withRecoveryCheck(.retryBlocked(mapping.userMessage, nil)))
        }
    }

    private func importCurrentProgressItem(
        _ context: ImportProgressRetryContext,
        traceContext: CoreImportTraceContext
    ) async throws -> FileEntrySnapshot {
        let sourceURL = URL(fileURLWithPath: context.sourcePath)
        guard let importer = importProgressImporter as? any CoreObservedFileImporting else {
            return try await importCurrentProgressItemWithoutTrace(context, sourceURL: sourceURL)
        }
        switch context.storageMode {
        case .copy:
            return try await importer.importCopiedFile(request: CoreObservedImportRequest(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy,
                traceContext: traceContext
            ))
        case .move:
            return try await importer.importMovedFile(request: CoreObservedImportRequest(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy,
                traceContext: traceContext
            ))
        case .indexOnly:
            return try await importer.importIndexedFile(request: CoreObservedImportRequest(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy,
                traceContext: traceContext
            ))
        }
    }

    private func importCurrentProgressItemWithoutTrace(
        _ context: ImportProgressRetryContext,
        sourceURL: URL
    ) async throws -> FileEntrySnapshot {
        switch context.storageMode {
        case .copy:
            try await importProgressImporter.importCopiedFile(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy
            )
        case .move:
            try await importProgressImporter.importMovedFile(
                repoPath: context.repoPath,
                sourceURL: sourceURL,
                overrideCategory: context.overrideCategory,
                overrideFilename: context.overrideFilename,
                duplicateStrategy: context.duplicateStrategy.coreStrategy
            )
        case .indexOnly:
            try await importProgressImporter.importIndexedFile(
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
        from state: ImportProgressRouteState,
        context: ImportProgressRetryContext
    ) async {
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

    func importProgressMapping(for error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }

    @MainActor
    private func finishStandaloneRetriedImport(
        _ entry: FileEntrySnapshot,
        from state: ImportProgressRouteState
    ) {
        importProgressControlState.clearQueueContinuation()
        route = Self.mainRoute(for: state.sourceOpening)
        toastMessage = entry.importCompletionMessage
        accessibilityAnnouncer.announce(entry.importCompletionMessage)
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
        let latestState: ImportProgressRouteState = if case let .importProgress(state) = route {
            state
        } else {
            fallbackState
        }
        finishContinuedImportProgressOutcome(outcome, retriedEntry: entry, fallbackState: latestState)
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
        var summary = outcome.progressSnapshot(currentPath: fallbackState.currentPath)
        if !fallbackState.items.isEmpty {
            summary.items = fallbackState.items
            summary.completed = fallbackState.items.filter { $0.phase == .done }.count
            summary.failed = fallbackState.items.filter { $0.phase == .failed }.count
            summary.total = max(summary.total, fallbackState.items.count)
            summary.remaining = 0
        }
        showImportEntryResults(summary)
    }
}
