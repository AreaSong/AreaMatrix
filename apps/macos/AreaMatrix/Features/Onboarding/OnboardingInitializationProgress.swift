import Foundation

extension OnboardingModel {
    @MainActor
    func beginMainOpening(repoPath: String, scanSession: ScanSessionSnapshot? = nil) -> UUID {
        let cancellationToken = UUID()
        openingCancellationToken = cancellationToken
        route = .mainLoading(MainLoadingState(
            repoPath: repoPath,
            startupRecovery: .checking,
            scanSession: scanSession,
            treeLoading: mainLoadingTreeLister != nil ? .loading : nil
        ))
        return cancellationToken
    }

    @MainActor
    func cancelMainOpening() {
        guard case let .mainLoading(state) = route else { return }

        openingCancellationToken = UUID()
        resetCancelledMainOpening(repoPath: state.repoPath)
        route = .validatePath
        toastMessage = L10n.string("Opening was cancelled. Repository configuration and user files were not changed.")
    }

    @MainActor
    func openExistingRepository(_ validation: RepoPathValidationSnapshot) async {
        initializationOpenErrorMapping = nil
        mainRepoRecoveryErrorMapping = nil
        let cancellationToken = beginMainOpening(repoPath: validation.repoPath)

        await Task.yield()
        guard openingCancellationToken == cancellationToken else { return }

        do {
            try await recoverMainOpeningResidue(repoPath: validation.repoPath, cancellationToken: cancellationToken)
            let loadingRefreshTask = makeMainLoadingRefreshTask(
                repoPath: validation.repoPath,
                cancellationToken: cancellationToken,
                shouldLoadAdoptSession: true,
                shouldLoadTree: true
            )
            defer { loadingRefreshTask.cancel() }
            let opening = try await emptyRepositoryOpener.openConfiguredRepository(repoPath: validation.repoPath)
            guard openingCancellationToken == cancellationToken else { return }
            settingsWriter.saveConfiguredRepoPath(validation.repoPath)
            finishSuccessfulRepositoryOpen(opening)
        } catch {
            guard openingCancellationToken == cancellationToken else { return }
            await updateMainRepoExternalRemoval(from: error, repoPath: validation.repoPath)
            await routeMainOpeningFailure(error, repoPath: validation.repoPath, cancellationToken: cancellationToken)
        }
    }

    @MainActor
    func retryMainRepositoryFromError(repoPath: String) async {
        guard !isRetryingMainRepository else { return }

        isRetryingMainRepository = true
        mainRepoRecoveryValidation = nil
        mainRepoRecoveryErrorMapping = nil
        defer {
            isRetryingMainRepository = false
        }

        do {
            let validation = try await initializedPathValidator.validateInitializedRepoPath(repoPath: repoPath)
            mainRepoRecoveryValidation = validation
            repositoryPathText = validation.repoPath
            repositoryPathValidation = validation
            await openExistingRepository(validation)
        } catch {
            await updateMainRepoExternalRemoval(from: error, repoPath: repoPath)
            await routeMainOpeningFailure(error, repoPath: repoPath)
        }
    }

    @MainActor
    func openInitializedRepository() async {
        guard case let .initializationDone(result) = route else { return }
        initializationOpenErrorMapping = nil
        let cancellationToken = beginMainOpening(repoPath: result.repoPath, scanSession: result.scanSession)

        await Task.yield()
        guard openingCancellationToken == cancellationToken else { return }

        do {
            try await recoverMainOpeningResidue(repoPath: result.repoPath, cancellationToken: cancellationToken)
            let loadingRefreshTask = makeMainLoadingRefreshTask(
                repoPath: result.repoPath,
                seedSession: result.scanSession,
                cancellationToken: cancellationToken,
                shouldLoadAdoptSession: result.mode == .adoptExisting,
                shouldLoadTree: true
            )
            defer { loadingRefreshTask.cancel() }
            let opening = try await openInitializedRepository(result)
            guard openingCancellationToken == cancellationToken else { return }
            finishSuccessfulRepositoryOpen(opening)
        } catch {
            guard openingCancellationToken == cancellationToken else { return }
            route = .initializationDone(result)
            initializationOpenErrorMapping = await openingFailureMapping(for: error)
        }
    }

    @MainActor
    func openInitializedRepositoryInFinder() async {
        guard case let .initializationDone(result) = route else { return }

        do {
            try finderOpener.openRepositoryInFinder(repoPath: result.repoPath)
            toastMessage = nil
        } catch {
            let message = L10n.format(
                "onboarding.initialization.openInFinderFailed",
                error.localizedDescription
            )
            toastMessage = message
            accessibilityAnnouncer.announce(message)
        }
    }

    @MainActor
    func resumeInterruptedInitialization(repoPath: String, scanSession: ScanSessionSnapshot?) async {
        guard let scanSession else {
            route = .initializationFailed(repoPath, nil, nil)
            return
        }

        let draft = RepositoryInitializationDraft(
            validation: Self.interruptedValidationSnapshot(repoPath: repoPath),
            mode: .adoptExisting,
            scanSession: scanSession
        )
        initializationScanSession = scanSession
        route = .initializing(draft)
        startInitializationProgressPolling(repoPath: repoPath, mode: .adoptExisting)
        defer { stopInitializationProgressPolling() }

        do {
            let report = try await scanSessionReader.resumeScanSession(
                repoPath: repoPath,
                scanSessionId: scanSession.id
            )
            initializationScanSession = Self.completedScanSession(scanSession, report: report)
            settingsWriter.saveConfiguredRepoPath(repoPath)
            route = .initializationDone(RepositoryInitializationResult(
                repoPath: repoPath,
                mode: .adoptExisting,
                scanSession: initializationScanSession,
                recoveryReport: initializationRecoveryReport
            ))
        } catch {
            await routeInitializationFailure(error, repoPath: repoPath)
        }
    }

    @MainActor
    func recoverMainOpeningResidue(repoPath: String, cancellationToken: UUID) async throws {
        do {
            let report = try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                try await self.startupRecoverer.recoverOnStartup(repoPath: repoPath)
            }
            guard openingCancellationToken == cancellationToken else { return }
            guard case var .mainLoading(state) = route, state.repoPath == repoPath else { return }
            state.startupRecovery = .completed(report.hasVisibleDetails ? report : nil)
            route = .mainLoading(state)
        } catch {
            guard openingCancellationToken == cancellationToken else { return }
            guard case var .mainLoading(state) = route, state.repoPath == repoPath else { return }
            let mapping = await openingFailureMapping(for: error)
            state.startupRecovery = .failed(mapping)
            route = .mainLoading(state)
            throw error
        }
    }

    @MainActor
    func cleanUpInterruptedInitialization(repoPath: String) async {
        repositoryPathText = repoPath
        repositoryPathError = nil
        repositoryPathErrorMapping = nil

        do {
            try await recoverStartupResidue(repoPath: repoPath)
            let validation = try await pathValidator.validateRepoPath(repoPath: repoPath)
            repositoryPathValidation = validation
            latestScanSession = nil

            if validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession) {
                latestScanSession = try await scanSessionReader.latestScanSession(repoPath: validation.repoPath)
                route = .dbRepairConfirm(DatabaseRepairRouteState(
                    repoPath: validation.repoPath,
                    scanSession: latestScanSession,
                    mapping: nil,
                    returnRoute: .validatePath
                ))
                toastMessage = L10n.string("onboarding.recovery.unfinishedScanRemains")
                return
            }

            await routeCleanRetryValidation(validation)
        } catch {
            await routeInitializationFailure(error, repoPath: repoPath)
        }
    }

    func initializeRepository(repoPath: String, mode: RepoInitModeSnapshot) async throws {
        switch mode {
        case .createEmpty:
            try await repositoryInitializer.initializeEmptyRepository(repoPath: repoPath)
        case .adoptExisting:
            try await repositoryInitializer.adoptExistingRepository(repoPath: repoPath)
        }
    }

    private func openInitializedRepository(
        _ result: RepositoryInitializationResult
    ) async throws -> RepositoryOpeningResult {
        switch result.mode {
        case .createEmpty:
            try await emptyRepositoryOpener.openEmptyRepository(repoPath: result.repoPath)
        case .adoptExisting:
            try await emptyRepositoryOpener.openAdoptedRepository(repoPath: result.repoPath)
        }
    }

    static func mainRoute(for opening: RepositoryOpeningResult) -> Route {
        opening.isEmpty ? .mainEmpty(opening) : .mainList(opening)
    }

    static func validationStillMatchesConfirmMode(
        _ validation: RepoPathValidationSnapshot,
        mode: RepoInitModeSnapshot
    ) -> Bool {
        guard validation.recommendedMode == mode, !validation.isInitialized else { return false }

        switch mode {
        case .createEmpty:
            return validation.isEmpty
        case .adoptExisting:
            return !validation.isEmpty
        }
    }

    func shouldLoadLatestScanSession(for validation: RepoPathValidationSnapshot) -> Bool {
        validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession)
    }

    @MainActor
    func startInitializationProgressPolling(repoPath: String, mode: RepoInitModeSnapshot) {
        stopInitializationProgressPolling()
        guard mode == .adoptExisting else { return }

        initializationProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshInitializationScanSession(repoPath: repoPath)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    @MainActor
    func stopInitializationProgressPolling() {
        initializationProgressTask?.cancel()
        initializationProgressTask = nil
    }

    @MainActor
    private func refreshInitializationScanSession(repoPath: String) async {
        guard isInitializingAdoptExisting(repoPath: repoPath) else { return }

        do {
            let session = try await scanSessionReader.latestScanSession(repoPath: repoPath)
            guard isInitializingAdoptExisting(repoPath: repoPath) else { return }
            initializationScanSession = session
            initializationProgressWarning = nil
        } catch {
            await recordInitializationProgressWarning(error, repoPath: repoPath)
        }
    }

    @MainActor
    private func recordInitializationProgressWarning(_ error: Error, repoPath: String) async {
        guard isInitializingAdoptExisting(repoPath: repoPath) else { return }

        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            guard isInitializingAdoptExisting(repoPath: repoPath) else { return }
            initializationProgressWarning = L10n.format(
                "onboarding.initialization.progressUnavailable",
                mapping.userMessage
            )
        } else {
            initializationProgressWarning = L10n.format(
                "onboarding.initialization.progressUnavailable",
                error.localizedDescription
            )
        }
    }

    private func isInitializingAdoptExisting(repoPath: String) -> Bool {
        guard case let .initializing(draft) = route else { return false }
        return draft.mode == .adoptExisting && draft.validation.repoPath == repoPath
    }

    @MainActor
    func recoverStartupResidue(repoPath: String) async throws {
        do {
            let report = try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                try await self.startupRecoverer.recoverOnStartup(repoPath: repoPath)
            }
            initializationRecoveryReport = report.hasVisibleDetails ? report : nil
        } catch {
            guard CoreErrorRawContextSnapshot.repoNotInitializedPath(from: error) != nil else { throw error }
            initializationRecoveryReport = nil
        }
    }

    @MainActor
    private func routeCleanRetryValidation(_ validation: RepoPathValidationSnapshot) async {
        repositoryPathError = validatePathBlockingMessage(for: validation)
        guard repositoryPathError == nil else {
            route = .validatePath
            return
        }

        if validation.isInitialized {
            await openExistingRepository(validation)
            return
        }

        route = .confirmRepositoryInitialization(RepositoryInitializationDraft(
            validation: validation,
            mode: validation.recommendedMode ?? .adoptExisting,
            scanSession: nil
        ))
    }

    private static func interruptedValidationSnapshot(repoPath: String) -> RepoPathValidationSnapshot {
        RepoPathValidationSnapshot(
            repoPath: repoPath,
            exists: true,
            isDirectory: true,
            isReadable: true,
            isWritable: true,
            isEmpty: false,
            isInitialized: true,
            isInsideAreaMatrix: false,
            isICloudPath: false,
            hasUnfinishedScanSession: true,
            availableCapacityBytes: nil,
            isExternalVolume: nil,
            recommendedMode: .adoptExisting,
            issues: [.unfinishedScanSession]
        )
    }

    private static func completedScanSession(
        _ session: ScanSessionSnapshot,
        report: ReindexReportSnapshot
    ) -> ScanSessionSnapshot {
        let finishedAt = Int64(Date().timeIntervalSince1970)
        return ScanSessionSnapshot(
            id: report.scanSessionId ?? session.id,
            kind: session.kind,
            status: .completed,
            lastPath: session.lastPath,
            inserted: report.inserted,
            updated: report.updated,
            skipped: report.skipped,
            startedAt: session.startedAt,
            updatedAt: finishedAt,
            finishedAt: finishedAt,
            errors: report.errors
        )
    }

    func openingFailureMapping(for error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }

    @MainActor
    func routeMainOpeningFailure(_ error: Error, repoPath: String, cancellationToken: UUID? = nil) async {
        let mapping = await openingFailureMapping(for: error)
        guard cancellationToken == nil || openingCancellationToken == cancellationToken else { return }
        mainRepoRecoveryErrorMapping = mapping
        if mapping.usesInlineRepositoryOpeningError {
            var state = MainLoadingState(repoPath: repoPath)
            if case let .mainLoading(currentState) = route, currentState.repoPath == repoPath {
                state = currentState
            }
            route = .mainLoading(state.withRepositoryOpeningError(mapping))
            return
        }
        routeMainRepositoryError(repoPath: repoPath, mapping: mapping)
    }
}
