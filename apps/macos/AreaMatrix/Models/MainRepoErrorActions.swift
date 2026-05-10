import Foundation

extension OnboardingModel {
    @MainActor
    func finishSuccessfulRepositoryOpen(_ opening: RepositoryOpeningResult) {
        let openedAt = Int64(Date().timeIntervalSince1970)
        settingsWriter.saveSuccessfulRepoOpen(repoPath: opening.config.repoPath, openedAt: openedAt)
        mainRepoLastOpenedAt = openedAt
        route = Self.mainRoute(for: opening)
        routeInterruptedImportSessionIfNeeded(opening: opening)
        consumeQueuedDockImportIfPossible()
        consumePendingExternalCreatedFileSignals()
    }

    @MainActor
    private func routeInterruptedImportSessionIfNeeded(opening: RepositoryOpeningResult) {
        Task { [weak self] in
            guard let self else { return }
            let repoPath = opening.config.repoPath
            guard let session = await importBatchSessionStore.loadSession(repoPath: repoPath),
                  session.isUnfinishedCopySession
            else { return }

            guard await shouldRouteInterruptedImportSession(repoPath: repoPath) else { return }
            await MainActor.run {
                guard self.currentMainRouteRepoPath == repoPath else { return }
                self.pendingImportEntry = nil
                self.route = .importResult(ImportResultRouteState(
                    sourceOpening: opening,
                    interruptedSession: session
                ))
                self.toastMessage = "检测到上次未完成的批量导入。"
            }
        }
    }

    private func shouldRouteInterruptedImportSession(repoPath: String) async -> Bool {
        do {
            _ = try await startupRecoverer.recoverOnStartup(repoPath: repoPath)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private var currentMainRouteRepoPath: String? {
        switch route {
        case let .mainEmpty(opening), let .mainList(opening), let .settingsGeneral(opening):
            opening.config.repoPath
        default:
            nil
        }
    }

    @MainActor
    func routeMainRepositoryError(repoPath: String, mapping: CoreErrorMappingSnapshot?) {
        mainRepoLastOpenedAt = lastKnownSuccessfulOpenAt(repoPath: repoPath)
        route = .mainRepoError(repoPath, mapping)
    }

    @MainActor
    func makeMainLoadingRefreshTask(
        repoPath: String,
        seedSession: ScanSessionSnapshot? = nil,
        cancellationToken: UUID,
        shouldLoadAdoptSession: Bool,
        shouldLoadTree: Bool
    ) -> Task<Void, Never> {
        Task { [weak self] in
            await self?.refreshMainLoadingState(
                repoPath: repoPath,
                seedSession: seedSession,
                cancellationToken: cancellationToken,
                shouldLoadAdoptSession: shouldLoadAdoptSession,
                shouldLoadTree: shouldLoadTree
            )
        }
    }

    @MainActor
    func reconnectMainRepositoryFolder(from repoPath: String) async {
        guard !isRetryingMainRepository else { return }
        guard case let .mainRepoError(currentRepoPath, _) = route, currentRepoPath == repoPath else {
            return
        }
        guard let selectedURL = directoryPicker.chooseDirectory() else { return }

        isRetryingMainRepository = true
        mainRepoRecoveryValidation = nil
        mainRepoRecoveryErrorMapping = nil
        defer {
            isRetryingMainRepository = false
        }

        let selectedPath = Self.normalizedRepositoryPath(selectedURL.path)
        do {
            let validation = try await initializedPathValidator.validateInitializedRepoPath(repoPath: selectedPath)
            try await verifyReconnectCandidate(originalRepoPath: repoPath, validation: validation)
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
    func revealMainRepositoryFolder(repoPath: String) {
        do {
            try finderOpener.openRepositoryInFinder(repoPath: repoPath)
            toastMessage = nil
        } catch {
            toastMessage = "Repository folder cannot be revealed."
        }
    }

    @MainActor
    func requestMainRepositoryDiagnosticsPrivacyConfirmation(repoPath: String) {
        guard case let .mainRepoError(currentRepoPath, _) = route, currentRepoPath == repoPath else {
            return
        }

        mainRepoDiagnostics = .confirmingPrivacy
    }

    @MainActor
    func cancelMainRepositoryDiagnosticsPrivacyConfirmation() {
        guard case .confirmingPrivacy = mainRepoDiagnostics else { return }

        mainRepoDiagnostics = .idle
    }

    @MainActor
    func collectMainRepositoryDiagnostics(repoPath: String) async {
        guard case let .mainRepoError(currentRepoPath, _) = route, currentRepoPath == repoPath else {
            return
        }
        guard case .confirmingPrivacy = mainRepoDiagnostics else {
            return
        }

        mainRepoDiagnostics = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            guard case let .mainRepoError(latestRepoPath, _) = route, latestRepoPath == repoPath else {
                return
            }
            mainRepoDiagnostics = .collected(snapshot)
        } catch {
            guard case let .mainRepoError(latestRepoPath, _) = route, latestRepoPath == repoPath else {
                return
            }
            mainRepoDiagnostics = await .failed(openingFailureMapping(for: error))
        }
    }

    private func lastKnownSuccessfulOpenAt(repoPath: String) -> Int64? {
        settingsReader.lastSuccessfulRepoOpenAt(repoPath: repoPath) ?? existingRepositoryMetadata?.lastOpenedAt
    }

    private func verifyReconnectCandidate(
        originalRepoPath: String,
        validation: RepoPathValidationSnapshot
    ) async throws {
        let original = Self.normalizedRepositoryPath(originalRepoPath)
        let selected = Self.normalizedRepositoryPath(validation.repoPath)
        if original == selected { return }

        let metadata = try await existingRepositoryMetadataReader.metadata(repoPath: validation.repoPath)
        guard let configuredRepoPath = metadata.configuredRepoPath else {
            throw CoreError.InvalidPath(path: validation.repoPath)
        }
        guard Self.normalizedRepositoryPath(configuredRepoPath) == original else {
            throw CoreError.InvalidPath(path: validation.repoPath)
        }
    }
}
