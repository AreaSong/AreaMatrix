import Foundation

extension OnboardingModel {
    @MainActor
    func handleImportMenuCommand() {
        switch route {
        case let .mainEmpty(opening), let .mainList(opening), let .settingsGeneral(opening):
            chooseImportSources(opening: opening)
        default:
            toastMessage = L10n.string("Open a repository before importing files.")
        }
    }

    @MainActor
    func chooseImportSources(opening: RepositoryOpeningResult) {
        guard let urls = importPicker.chooseImportURLs() else { return }
        startImportEntry(opening: opening, source: .filePicker, urls: urls)
    }

    @MainActor
    func startImportEntry(
        opening: RepositoryOpeningResult,
        source: ImportEntrySource,
        urls: [URL],
        destination: ImportEntryDestination = .autoClassify
    ) {
        let fileURLs = Self.validImportFileURLs(from: urls)
        guard !fileURLs.isEmpty else {
            toastMessage = L10n.string("Cannot import these items")
            accessibilityAnnouncer.announce("Cannot import these items")
            return
        }

        pendingImportEntry = ImportEntryRequest(
            repoPath: opening.config.repoPath,
            source: source,
            destination: destination,
            urls: fileURLs,
            kind: ImportEntryKind.resolved(for: fileURLs),
            availableCategories: resolvedImportCategories(opening: opening, destination: destination),
            defaultStorageMode: ImportSingleFileStorageMode(coreSnapshotValue: opening.config.defaultMode),
            allowReplaceDuringImport: opening.config.allowReplaceDuringImport,
            isTrashAvailable: systemCapabilityChecker.isTrashAvailable()
        )
        toastMessage = nil
    }

    @MainActor
    func startImportConflictBatchReview(
        opening: RepositoryOpeningResult,
        route: ImportConflictBatchRoute
    ) {
        let conflictIDs = route.conflictIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !route.importSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !conflictIDs.isEmpty else {
            toastMessage = L10n.string("No active import conflicts to review.")
            return
        }
        let placeholderURLs = conflictIDs.map { URL(fileURLWithPath: "/.areamatrix/import-conflicts/\($0)") }
        pendingImportEntry = ImportEntryRequest(
            repoPath: opening.config.repoPath,
            source: .importConflictBatch(route.source),
            destination: .autoClassify,
            urls: placeholderURLs,
            kind: .multipleItems(placeholderURLs.count),
            availableCategories: opening.availableImportCategories,
            defaultStorageMode: ImportSingleFileStorageMode(coreSnapshotValue: opening.config.defaultMode),
            allowReplaceDuringImport: opening.config.allowReplaceDuringImport,
            isTrashAvailable: systemCapabilityChecker.isTrashAvailable(),
            importSessionID: route.importSessionID,
            importConflictIDs: conflictIDs
        )
        toastMessage = nil
    }

    @MainActor
    func dismissImportEntry() {
        pendingImportEntry = nil
        consumeQueuedDockImportIfPossible()
    }

    @MainActor
    func switchImportEntryToLocalRepository() {
        pendingImportEntry = nil
        showChoosePath()
    }

    @MainActor
    func beginImportEntryProgress(currentPath: String) {
        beginImportEntryProgress(currentPath: currentPath, storageMode: .copy)
    }

    @MainActor
    func beginImportEntryProgress(currentPath: String, storageMode: ImportSingleFileStorageMode) {
        guard let opening = currentOpeningForImportOrProgress else { return }
        importProgressControlState.reset()
        pendingImportEntry = nil
        route = .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: currentPath,
            storageMode: storageMode
        ))
    }

    @MainActor
    func beginImportEntryProgress(
        currentPath: String,
        retryContext: ImportProgressRetryContext
    ) {
        guard let opening = currentOpeningForImportOrProgress else { return }
        importProgressControlState.reset()
        pendingImportEntry = nil
        route = .importProgress(ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: currentPath,
            storageMode: retryContext.storageMode,
            retryContext: retryContext,
            isRepositoryFinderAvailable: systemCapabilityChecker.repositoryFinderAvailability(
                repoPath: opening.config.repoPath
            )
        ))
    }

    @MainActor
    func updateImportEntryProgress(_ progress: ImportBatchProgressSnapshot) {
        guard let opening = currentOpeningForImportOrProgress else { return }
        pendingImportEntry = nil
        let stopState: ImportProgressStopState = if importProgressControlState.didStopAfterCurrentFile {
            .stopped
        } else if importProgressControlState.isStopAfterCurrentFileRequested {
            .stopping
        } else {
            .idle
        }
        let nextState = ImportProgressRouteState(
            sourceOpening: opening,
            currentPath: progress.currentPath,
            status: .running,
            completed: progress.completed,
            failed: progress.failed,
            remaining: progress.remaining,
            skipped: progress.skipped,
            pending: progress.pending,
            items: progress.items,
            stopState: stopState
        )
        route = .importProgress(nextState)
        if importProgressControlState.didStopAfterCurrentFile {
            showImportResult(from: nextState)
        }
    }

    @MainActor
    func showImportEntryResults(_ progress: ImportBatchProgressSnapshot) {
        guard let opening = currentOpeningForImportOrProgress else { return }
        pendingImportEntry = nil
        importProgressControlState.clearQueueContinuation()
        toastMessage = nil
        route = .importResult(ImportResultRouteState(sourceOpening: opening, progress: progress))
    }

    @MainActor
    func failImportEntry(currentPath: String, mapping: CoreErrorMappingSnapshot) {
        failImportEntry(
            progress: ImportBatchProgressSnapshot(
                completed: 0,
                failed: 1,
                total: 1,
                remaining: 0,
                currentPath: currentPath
            ),
            mapping: mapping
        )
    }

    @MainActor
    func failImportEntry(progress: ImportBatchProgressSnapshot, mapping: CoreErrorMappingSnapshot) {
        failImportEntry(progress: progress, mapping: mapping, retryContext: nil)
    }

    @MainActor
    func failImportEntry(
        progress: ImportBatchProgressSnapshot,
        mapping: CoreErrorMappingSnapshot,
        retryContext: ImportProgressRetryContext?,
        recoveryCheck: ImportProgressRecoveryCheckState
    ) {
        applyImportEntryFailure(
            progress: progress,
            mapping: mapping,
            retryContext: retryContext,
            recoveryCheck: recoveryCheck
        )
    }

    @MainActor
    func failImportEntry(
        progress: ImportBatchProgressSnapshot,
        mapping: CoreErrorMappingSnapshot,
        retryContext: ImportProgressRetryContext?,
        recoveryCheck: ImportProgressRecoveryCheckState?
    ) {
        applyImportEntryFailure(
            progress: progress,
            mapping: mapping,
            retryContext: retryContext,
            recoveryCheck: recoveryCheck
        )
    }

    @MainActor
    func failImportEntry(
        progress: ImportBatchProgressSnapshot,
        mapping: CoreErrorMappingSnapshot,
        retryContext: ImportProgressRetryContext?
    ) {
        applyImportEntryFailure(progress: progress, mapping: mapping, retryContext: retryContext, recoveryCheck: nil)
    }

    @MainActor
    private func applyImportEntryFailure(
        progress: ImportBatchProgressSnapshot,
        mapping: CoreErrorMappingSnapshot,
        retryContext: ImportProgressRetryContext?,
        recoveryCheck: ImportProgressRecoveryCheckState?
    ) {
        guard case let .importProgress(state) = route else { return }
        guard mapping.recoverability == .fatal else {
            showImportEntryResults(progress)
            return
        }
        route = .importProgress(ImportProgressRouteState(
            sourceOpening: state.sourceOpening,
            currentPath: progress.currentPath,
            status: .failed(mapping),
            completed: progress.completed,
            failed: progress.failed,
            remaining: progress.remaining,
            skipped: progress.skipped,
            pending: progress.pending,
            items: progress.items,
            retryContext: retryContext ?? state.retryContext,
            recoveryCheck: recoveryCheck,
            diagnostics: state.diagnostics,
            stopState: state.stopState,
            isRepositoryFinderAvailable: state.isRepositoryFinderAvailable
        ))
    }

    @MainActor
    func showImportEntryExistingFile(relativePath: String) {
        guard let request = pendingImportEntry else { return }
        do {
            try fileRevealer.revealFile(repoPath: request.repoPath, relativePath: relativePath)
            toastMessage = nil
        } catch {
            toastMessage = L10n.string("Existing file cannot be shown in Finder.")
        }
    }

    @MainActor
    func finishImportEntry(repoPath: String, entry: FileEntrySnapshot) async {
        do {
            let opening = try await emptyRepositoryOpener.openConfiguredRepository(repoPath: repoPath)
            finishSuccessfulRepositoryOpen(opening)
            toastMessage = L10n.format("import.single.imported-file", entry.currentName)
            accessibilityAnnouncer.announce(L10n.format("import.single.imported-file", entry.currentName))
        } catch {
            await routeMainOpeningFailure(error, repoPath: repoPath)
        }
    }

    @MainActor
    func handleDockOpenFiles(_ urls: [URL]) {
        let fileURLs = Self.validImportFileURLs(from: urls)
        guard !fileURLs.isEmpty else { return }
        queuedDockImportBatches.append(fileURLs)
        consumeQueuedDockImportIfPossible()
    }

    @MainActor
    func consumePendingDockOpenRequests() {
        for urls in AreaMatrixDockOpenRelay.takePendingBatches() {
            handleDockOpenFiles(urls)
        }
    }

    @MainActor
    func consumeQueuedDockImportIfPossible() {
        guard pendingImportEntry == nil else { return }
        guard let opening = currentOpeningForImport else { return }
        guard queuedDockImportBatches.isEmpty == false else { return }
        let urls = queuedDockImportBatches.removeFirst()
        startImportEntry(opening: opening, source: .dockOpenFile, urls: urls)
    }

    private func resolvedImportCategories(
        opening: RepositoryOpeningResult,
        destination: ImportEntryDestination
    ) -> [String] {
        var categories = opening.availableImportCategories
        if case let .category(slug) = destination, !categories.contains(slug) {
            categories.append(slug)
        }
        return categories
    }

    private var currentOpeningForImport: RepositoryOpeningResult? {
        switch route {
        case let .mainEmpty(opening), let .mainList(opening), let .settingsGeneral(opening):
            opening
        default:
            nil
        }
    }

    private var currentOpeningForImportOrProgress: RepositoryOpeningResult? {
        switch route {
        case let .importProgress(state):
            state.sourceOpening
        default:
            currentOpeningForImport
        }
    }

    private static func validImportFileURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            url.isFileURL && !url.path.isEmpty
        }
    }
}
