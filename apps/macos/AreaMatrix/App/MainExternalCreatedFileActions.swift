import Foundation

extension OnboardingModel {
    @MainActor
    func consumePendingExternalCreatedFileSignals() {
        let signals = AreaMatrixExternalCreatedFileRelay.takePendingSignals(
            matchingRepoPath: currentMainRepositoryPath
        )
        for signal in signals {
            handleExternalCreatedFile(signal)
        }
    }

    @MainActor
    @discardableResult
    func handleExternalCreatedFile(_ signal: MainExternalCreatedFileSignal) -> Bool {
        guard let pending = MainPendingExternalCreatedFileEvent(signal: signal) else { return false }
        guard currentMainRepositoryPath == pending.repoPath else { return false }

        pendingExternalCreatedFileEvent = pending
        toastMessage = nil
        return true
    }

    @MainActor
    func externalCreatedEvent(for opening: RepositoryOpeningResult) -> MainExternalCreatedFileEvent? {
        guard pendingExternalCreatedFileEvent?.repoPath == normalizedMainRepositoryPath(opening.config.repoPath) else {
            return nil
        }
        return pendingExternalCreatedFileEvent?.event
    }

    @MainActor
    func finishExternalCreatedFileEvent(_ event: MainExternalCreatedFileEvent) {
        guard pendingExternalCreatedFileEvent?.event == event else { return }
        pendingExternalCreatedFileEvent = nil
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
