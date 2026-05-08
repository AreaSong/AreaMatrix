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
        case .mainEmpty(let opening), .mainList(let opening), .settingsGeneral(let opening):
            return normalizedMainRepositoryPath(opening.config.repoPath)
        case .importProgress(let state):
            return normalizedMainRepositoryPath(state.sourceOpening.config.repoPath)
        case .importResult(let state):
            return normalizedMainRepositoryPath(state.sourceOpening.config.repoPath)
        default:
            return nil
        }
    }

    private func normalizedMainRepositoryPath(_ repoPath: String) -> String {
        URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
    }
}
