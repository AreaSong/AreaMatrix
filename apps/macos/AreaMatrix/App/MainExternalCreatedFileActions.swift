import Foundation

extension OnboardingModel {
    @MainActor
    func consumePendingExternalCreatedFileSignals() {
        consumePendingExternalSyncWindows(repoPath: currentMainRepositoryPath)
    }

    @MainActor
    func consumePendingExternalSyncWindows(repoPath: String?) {
        _ = handleExternalSyncWindows(
            AreaMatrixExternalCreatedFileRelay.takePendingWindows(matchingRepoPath: repoPath)
        )
    }

    @MainActor
    @discardableResult
    func handleExternalCreatedFile(_ signal: MainExternalCreatedFileSignal) -> Bool {
        handleExternalCreatedFiles([signal])
    }

    @MainActor
    @discardableResult
    func handleExternalCreatedFiles(_ signals: [MainExternalCreatedFileSignal]) -> Bool {
        var windows: [MainExternalSyncWindow] = []
        for signal in signals {
            guard let window = MainExternalSyncWindow(signals: [signal]) else { continue }
            Self.mergeExternalSyncWindow(window, into: &windows)
        }
        return handleExternalSyncWindows(windows)
    }

    @MainActor
    @discardableResult
    func handleExternalSyncWindows(_ windows: [MainExternalSyncWindow]) -> Bool {
        guard let currentMainRepositoryPath else { return false }
        let accepted = windows.filter { $0.repoPath == currentMainRepositoryPath }
        guard !accepted.isEmpty else { return false }

        for window in accepted {
            Self.mergeExternalSyncWindow(window, into: &pendingExternalSyncWindows)
        }
        pendingExternalSyncWindows = pendingExternalSyncWindows.enumerated().sorted { lhs, rhs in
            if lhs.element.cursorWatermark == rhs.element.cursorWatermark { return lhs.offset < rhs.offset }
            return lhs.element.cursorWatermark < rhs.element.cursorWatermark
        }.map(\.element)
        toastMessage = nil
        return true
    }

    @MainActor
    func externalSyncWindows(for opening: RepositoryOpeningResult) -> [MainExternalSyncWindow] {
        let repoPath = normalizedMainRepositoryPath(opening.config.repoPath)
        return pendingExternalSyncWindows.filter { $0.repoPath == repoPath }
    }

    @MainActor
    func finishExternalSyncWindow(_ window: MainExternalSyncWindow) {
        pendingExternalSyncWindows.removeAll { $0.id == window.id }
    }

    @MainActor
    func externalCreatedEvents(for opening: RepositoryOpeningResult) -> [MainExternalCreatedFileEvent] {
        externalSyncWindows(for: opening).first?.events ?? []
    }

    @MainActor
    func finishExternalCreatedFileEvents(_ events: [MainExternalCreatedFileEvent]) {
        guard let window = pendingExternalSyncWindows.first(where: { $0.events == events }) else { return }
        finishExternalSyncWindow(window)
    }

    @MainActor
    func handleExternalWatcherRecovery(_ request: MainExternalWatcherRecoveryRequest) {
        guard currentMainRepositoryPath == request.repoPath else { return }
        pendingExternalSyncWindows.removeAll { $0.repoPath == request.repoPath }

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
                try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                    try await self.externalChangesSyncer.setFSEventCursor(
                        repoPath: repoPath,
                        lastEventID: seed.eventID
                    )
                }
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

    private static func mergeExternalSyncWindow(
        _ window: MainExternalSyncWindow,
        into windows: inout [MainExternalSyncWindow]
    ) {
        if let index = windows.firstIndex(where: { existing in
            existing.repoPath == window.repoPath && existing.cursorWatermark == window.cursorWatermark
        }), let merged = windows[index].merging(window) {
            windows[index] = merged
        } else if !windows.contains(where: { $0.id == window.id }) {
            windows.append(window)
        }
    }
}
