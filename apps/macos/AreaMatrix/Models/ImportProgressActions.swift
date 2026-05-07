import Foundation

extension OnboardingModel {
    @MainActor
    func retryCurrentImportProgressItem() async {
        guard case .importProgress(let state) = route else { return }
        guard state.canRetryCurrentItem, let context = state.retryContext else { return }

        route = .importProgress(state.withRecoveryCheck(.checking))
        do {
            let entry = try await importCurrentProgressItem(context)
            finishRetriedImportProgressItem(entry, from: state)
        } catch {
            await failRetriedImportProgressItem(error, context: context)
        }
    }

    @MainActor
    func stopImportProgressAfterCurrentFile() {
        guard case .importProgress(let state) = route else { return }
        route = .importProgress(state.withStopState(.stopping))
        route = .importProgress(state.withStopState(.stopped))
    }

    @MainActor
    func stopImportProgressAndViewResults() {
        guard case .importProgress(let state) = route else { return }
        toastMessage = state.resultSummaryText
        route = Self.mainRoute(for: state.sourceOpening)
        consumeQueuedDockImportIfPossible()
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
        guard context.storageMode == .move || context.storageMode == .indexOnly else { return }

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
        case .copy:
            throw CoreError.Internal(message: "Only C1-07 move and C1-08 index retry are available from S1-20.")
        }
    }

    @MainActor
    private func finishRetriedImportProgressItem(
        _ entry: FileEntrySnapshot,
        from state: ImportProgressRouteState
    ) {
        route = Self.mainRoute(for: state.sourceOpening)
        toastMessage = "已导入：\(entry.currentName)"
        accessibilityAnnouncer.announce("已导入：\(entry.currentName)")
        consumeQueuedDockImportIfPossible()
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
}
