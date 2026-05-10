import Foundation

extension OnboardingModel {
    @MainActor
    func cancelMainOpening() {
        guard case let .mainLoading(state) = route else { return }

        openingCancellationToken = UUID()
        resetCancelledMainOpening(repoPath: state.repoPath)
        route = .validatePath
        toastMessage = "Opening was cancelled. Repository configuration and user files were not changed."
    }

    @MainActor
    func openExistingRepository(_ validation: RepoPathValidationSnapshot) async {
        initializationOpenErrorMapping = nil
        mainRepoRecoveryErrorMapping = nil
        let cancellationToken = UUID()
        openingCancellationToken = cancellationToken
        route = .mainLoading(MainLoadingState(
            repoPath: validation.repoPath,
            startupRecovery: .checking,
            treeLoading: mainLoadingTreeLister != nil ? .loading : nil
        ))

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
        let cancellationToken = UUID()
        openingCancellationToken = cancellationToken
        route = .mainLoading(MainLoadingState(
            repoPath: result.repoPath,
            startupRecovery: .checking,
            scanSession: result.scanSession,
            treeLoading: mainLoadingTreeLister != nil ? .loading : nil
        ))

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
            let message = "无法在 Finder 中打开资料库：\(error.localizedDescription)"
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
    func refreshMainLoadingState(
        repoPath: String,
        seedSession: ScanSessionSnapshot? = nil,
        cancellationToken: UUID,
        shouldLoadAdoptSession: Bool,
        shouldLoadTree: Bool
    ) async {
        async let scanResult = loadMainLoadingScanSession(
            repoPath: repoPath,
            seedSession: seedSession,
            shouldLoadAdoptSession: shouldLoadAdoptSession
        )
        async let treeResult = loadMainLoadingTree(repoPath: repoPath, shouldLoadTree: shouldLoadTree)

        let loadingUpdate = await MainLoadingRefreshUpdate(
            scanResult: scanResult,
            treeResult: treeResult
        )
        applyMainLoadingState(repoPath: repoPath, cancellationToken: cancellationToken, update: loadingUpdate)
    }

    private func loadMainLoadingScanSession(
        repoPath: String,
        seedSession: ScanSessionSnapshot?,
        shouldLoadAdoptSession: Bool
    ) async -> MainLoadingScanRefreshResult? {
        guard shouldLoadAdoptSession else { return nil }
        if seedSession?.kind == .adopt, seedSession?.status == .completed { return nil }

        do {
            return try await MainLoadingScanRefreshResult(
                scanSession: scanSessionReader.latestScanSession(repoPath: repoPath) ?? seedSession,
                scanSessionErrorMapping: nil
            )
        } catch {
            return await MainLoadingScanRefreshResult(
                scanSession: seedSession,
                scanSessionErrorMapping: openingFailureMapping(for: error)
            )
        }
    }

    private func loadMainLoadingTree(
        repoPath: String,
        shouldLoadTree: Bool
    ) async -> MainLoadingTreeRefreshResult? {
        guard shouldLoadTree, let mainLoadingTreeLister else { return nil }

        do {
            let tree = try await mainLoadingTreeLister.listTree(repoPath: repoPath, locale: Self.mainLoadingTreeLocale)
            return MainLoadingTreeRefreshResult(treeLoading: .loaded(tree))
        } catch {
            return await MainLoadingTreeRefreshResult(
                treeLoading: .failed(openingFailureMapping(for: error))
            )
        }
    }

    @MainActor
    private func applyMainLoadingState(
        repoPath: String,
        cancellationToken: UUID,
        update: MainLoadingRefreshUpdate
    ) {
        guard openingCancellationToken == cancellationToken else { return }
        guard case let .mainLoading(currentState) = route else { return }
        let scanSession = update.scanResult?.scanSession ?? currentState.scanSession
        let scanSessionErrorMapping = update.scanResult.map(\.scanSessionErrorMapping) ?? currentState
            .scanSessionErrorMapping
        let treeLoading = update.treeResult?.treeLoading ?? currentState.treeLoading

        route = .mainLoading(MainLoadingState(
            repoPath: repoPath,
            startupRecovery: currentState.startupRecovery,
            scanSession: scanSession,
            scanSessionErrorMapping: scanSessionErrorMapping,
            treeLoading: treeLoading,
            repositoryOpeningErrorMapping: currentState.repositoryOpeningErrorMapping
        ))
    }

    @MainActor
    func retryMainLoadingTree() async {
        guard case var .mainLoading(state) = route else { return }
        guard mainLoadingTreeLister != nil else { return }

        state.treeLoading = .loading
        route = .mainLoading(state)

        guard let result = await loadMainLoadingTree(repoPath: state.repoPath, shouldLoadTree: true) else { return }
        guard case var .mainLoading(latestState) = route, latestState.repoPath == state.repoPath else { return }

        latestState.treeLoading = result.treeLoading
        route = .mainLoading(latestState)
    }

    @MainActor
    func recoverMainOpeningResidue(repoPath: String, cancellationToken: UUID) async throws {
        do {
            let report = try await startupRecoverer.recoverOnStartup(repoPath: repoPath)
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
                toastMessage = "仍检测到未完成的扫描，请返回来源页继续处理。"
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

    private static var mainLoadingTreeLocale: String {
        Locale.preferredLanguages.first ?? "zh-Hans"
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

        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            guard isInitializingAdoptExisting(repoPath: repoPath) else { return }
            initializationProgressWarning = "无法读取接管进度：\(mapping.userMessage)"
        } else {
            initializationProgressWarning = "无法读取接管进度：\(error.localizedDescription)"
        }
    }

    private func isInitializingAdoptExisting(repoPath: String) -> Bool {
        guard case let .initializing(draft) = route else { return false }
        return draft.mode == .adoptExisting && draft.validation.repoPath == repoPath
    }

    @MainActor
    func recoverStartupResidue(repoPath: String) async throws {
        do {
            let report = try await startupRecoverer.recoverOnStartup(repoPath: repoPath)
            initializationRecoveryReport = report.hasVisibleDetails ? report : nil
        } catch CoreError.RepoNotInitialized(_) {
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
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
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
