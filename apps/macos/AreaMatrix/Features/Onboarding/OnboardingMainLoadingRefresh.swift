import Foundation

extension OnboardingModel {
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

    private static var mainLoadingTreeLocale: String {
        Locale.preferredLanguages.first ?? "zh-Hans"
    }
}
