import Foundation

extension OnboardingModel {
    func initializeRepository(repoPath: String, mode: RepoInitModeSnapshot) async throws {
        switch mode {
        case .createEmpty:
            try await repositoryInitializer.initializeEmptyRepository(repoPath: repoPath)
        case .adoptExisting:
            try await repositoryInitializer.adoptExistingRepository(repoPath: repoPath)
        }
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
        guard case .initializing(let draft) = route else { return false }
        return draft.mode == .adoptExisting && draft.validation.repoPath == repoPath
    }
}
