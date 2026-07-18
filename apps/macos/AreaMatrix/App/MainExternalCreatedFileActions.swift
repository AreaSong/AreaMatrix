import Foundation

extension OnboardingModel {
    @MainActor
    func consumePendingExternalCreatedFileSignals() {
        let signals = AreaMatrixExternalCreatedFileRelay.takePendingSignals(
            matchingRepoPath: currentMainRepositoryPath
        )
        _ = handleExternalCreatedFiles(signals)
    }

    @MainActor
    @discardableResult
    func handleExternalCreatedFile(_ signal: MainExternalCreatedFileSignal) -> Bool {
        handleExternalCreatedFiles([signal])
    }

    @MainActor
    @discardableResult
    func handleExternalCreatedFiles(_ signals: [MainExternalCreatedFileSignal]) -> Bool {
        let pending = signals.compactMap(MainPendingExternalCreatedFileEvent.init(signal:))
            .filter { currentMainRepositoryPath == $0.repoPath }
        guard !pending.isEmpty else { return false }

        for item in pending {
            if let index = pendingExternalCreatedFileEvents.firstIndex(where: {
                $0.repoPath == item.repoPath && $0.event.relativePath == item.event.relativePath
            }) {
                if pendingExternalCreatedFileEvents[index].event.fsEventID <= item.event.fsEventID {
                    pendingExternalCreatedFileEvents[index] = item
                }
            } else {
                pendingExternalCreatedFileEvents.append(item)
            }
        }
        pendingExternalCreatedFileEvents.sort { lhs, rhs in
            if lhs.event.fsEventID == rhs.event.fsEventID { return lhs.event.relativePath < rhs.event.relativePath }
            return lhs.event.fsEventID < rhs.event.fsEventID
        }
        toastMessage = nil
        return true
    }

    @MainActor
    func externalCreatedEvents(for opening: RepositoryOpeningResult) -> [MainExternalCreatedFileEvent] {
        let repoPath = normalizedMainRepositoryPath(opening.config.repoPath)
        return pendingExternalCreatedFileEvents
            .filter { $0.repoPath == repoPath }
            .map(\.event)
    }

    @MainActor
    func finishExternalCreatedFileEvents(_ events: [MainExternalCreatedFileEvent]) {
        let handled = Set(events)
        pendingExternalCreatedFileEvents.removeAll { handled.contains($0.event) }
    }

    @MainActor
    func handleExternalWatcherRecovery(_ request: MainExternalWatcherRecoveryRequest) {
        guard currentMainRepositoryPath == request.repoPath else { return }
        pendingExternalCreatedFileEvents.removeAll { $0.repoPath == request.repoPath }

        switch request.kind {
        case .rescanRequired:
            if let resumeEventID = request.resumeEventID {
                pendingWatcherRescanSeed = (request.repoPath, resumeEventID)
            }
            openMainRepositoryRepair(repoPath: request.repoPath)
        case .rootChanged, .startupFailed:
            let mapping = CoreErrorMappingSnapshot(
                kind: request.kind == .rootChanged ? .fileNotFound : .internal,
                userMessage: request.kind == .rootChanged
                    ? "Repository folder is unavailable."
                    : "Filesystem monitoring could not start.",
                severity: .high,
                suggestedAction: request.kind == .rootChanged
                    ? "Reconnect the repository folder before continuing."
                    : "Retry opening the repository. If the problem persists, collect diagnostics.",
                recoverability: .userActionRequired,
                rawContext: request.reason
            )
            routeMainRepositoryError(repoPath: request.repoPath, mapping: mapping)
        }
    }

    @MainActor
    func finishWatcherRecoveryRescan(repoPath: String) async {
        if let seed = pendingWatcherRescanSeed,
           seed.repoPath == normalizedMainRepositoryPath(repoPath) {
            do {
                try await externalChangesSyncer.setFSEventCursor(
                    repoPath: repoPath,
                    lastEventID: seed.eventID
                )
                pendingWatcherRescanSeed = nil
            } catch {
                let mapping = await openingFailureMapping(for: error)
                routeMainRepositoryError(repoPath: repoPath, mapping: mapping)
                return
            }
        }
        await retryMainRepositoryFromError(repoPath: repoPath)
    }

    private var currentMainRepositoryPath: String? {
        switch route {
        case let .mainEmpty(opening), let .mainList(opening), let .settingsGeneral(opening):
            normalizedMainRepositoryPath(opening.config.repoPath)
        case let .importProgress(state):
            normalizedMainRepositoryPath(state.sourceOpening.config.repoPath)
        case let .importResult(state):
            normalizedMainRepositoryPath(state.sourceOpening.config.repoPath)
        default:
            nil
        }
    }

    private func normalizedMainRepositoryPath(_ repoPath: String) -> String {
        URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
    }
}
