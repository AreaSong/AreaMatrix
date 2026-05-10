import Foundation

extension OnboardingModel {
    @MainActor
    func consumePendingExternalCreatedFileSignals() {
        for signal in AreaMatrixExternalCreatedFileRelay.takePendingSignals() {
            handleExternalCreatedFile(signal)
        }
    }

    @MainActor
    func handleExternalCreatedFile(_ signal: MainExternalCreatedFileSignal) {
        guard let pending = MainPendingExternalCreatedFileEvent(signal: signal) else { return }
        guard currentMainRepositoryPath == pending.repoPath else { return }

        pendingExternalCreatedFileEvent = pending
        toastMessage = nil
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
