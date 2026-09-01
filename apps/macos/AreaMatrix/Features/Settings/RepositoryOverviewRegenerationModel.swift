import Combine
import Foundation

struct RepositoryOverviewSharedOperation: Equatable {
    var session: CoreOverviewRegenerationSessionSnapshot
    var initiatorID: UUID?
}

final class OverviewRegenerationCoordinator: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    @MainActor private(set) var operations: [String: RepositoryOverviewSharedOperation] = [:]

    @MainActor
    func operation(for repoPath: String) -> RepositoryOverviewSharedOperation? {
        operations[repoPath]
    }

    @MainActor
    func publish(
        _ session: CoreOverviewRegenerationSessionSnapshot,
        repoPath: String,
        initiatorID: UUID?
    ) {
        let retainedInitiator = initiatorID ?? operations[repoPath]?.initiatorID
        operations[repoPath] = RepositoryOverviewSharedOperation(
            session: session,
            initiatorID: retainedInitiator
        )
        objectWillChange.send()
    }

    @MainActor
    func clear(repoPath: String) {
        operations.removeValue(forKey: repoPath)
        objectWillChange.send()
    }
}

struct RepositoryOverviewRegenerationError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

enum RepositoryOverviewRegenerationPhase: Equatable {
    case idle
    case loading
    case preflight(CoreOverviewRegenerationPlanSnapshot)
    case starting
    case committing
    case canceling
    case recovering
    case failed(RepositoryOverviewRegenerationError)

    var isBusy: Bool {
        switch self {
        case .loading, .starting, .committing, .canceling, .recovering: true
        case .idle, .preflight, .failed: false
        }
    }
}

@MainActor
final class RepositoryOverviewRegenerationModel: ObservableObject {
    @Published private(set) var languageStatus: CoreOverviewLanguageStatusSnapshot?
    @Published private(set) var phase: RepositoryOverviewRegenerationPhase = .idle

    let repoPath: String
    let windowID: UUID
    let coordinator: OverviewRegenerationCoordinator

    private let bridge: any CoreOverviewRegenerating
    private let errorMapper: any CoreErrorMapping
    private var concreteContentLocale: String?
    private var coordinatorObservation: AnyCancellable?
    private var loadGeneration = 0
    private var prepareGeneration = 0
    private var languageStatusGeneration = 0

    init(
        repoPath: String,
        windowID: UUID = UUID(),
        bridge: any CoreOverviewRegenerating,
        coordinator: OverviewRegenerationCoordinator,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.windowID = windowID
        self.bridge = bridge
        self.coordinator = coordinator
        self.errorMapper = errorMapper
        coordinatorObservation = self.coordinator.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var sharedOperation: RepositoryOverviewSharedOperation? {
        coordinator.operation(for: repoPath)
    }

    var canInteractWithSharedOperation: Bool {
        sharedOperation?.initiatorID == windowID
    }

    func load(contentLocale: String) async {
        guard !repoPath.isEmpty else { return }
        languageStatusGeneration &+= 1
        loadGeneration &+= 1
        let requestGeneration = loadGeneration
        concreteContentLocale = contentLocale
        phase = .loading
        do {
            let status = try await bridge.overviewLanguageStatus(
                repoPath: repoPath,
                contentLocale: contentLocale
            )
            guard requestGeneration == loadGeneration, !Task.isCancelled else { return }
            languageStatus = status
            phase = .idle
        } catch {
            guard requestGeneration == loadGeneration, !Task.isCancelled else { return }
            phase = await .failed(mappedError(error))
        }
    }

    func prepare() async {
        guard let concreteContentLocale, !phase.isBusy, sharedOperation == nil else { return }
        prepareGeneration &+= 1
        let requestGeneration = prepareGeneration
        phase = .loading
        do {
            let plan = try await bridge.prepareOverviewRegeneration(
                repoPath: repoPath,
                contentLocale: concreteContentLocale
            )
            guard requestGeneration == prepareGeneration, !Task.isCancelled else { return }
            phase = .preflight(plan)
        } catch {
            guard requestGeneration == prepareGeneration, !Task.isCancelled else { return }
            phase = await .failed(mappedError(error))
        }
    }

    func cancelPreflight() {
        guard case .preflight = phase else { return }
        phase = .idle
    }

    func stageConfirmedPlan() async {
        guard case let .preflight(plan) = phase, sharedOperation == nil else { return }
        phase = .starting
        do {
            let session = try await bridge.startOverviewRegeneration(repoPath: repoPath, plan: plan)
            coordinator.publish(session, repoPath: repoPath, initiatorID: windowID)
            phase = .idle
        } catch {
            phase = await .failed(mappedError(error))
        }
    }

    func commit() async {
        guard canInteractWithSharedOperation,
              let session = sharedOperation?.session,
              session.status == .readyToCommit
        else { return }
        phase = .committing
        do {
            let committed = try await bridge.commitOverviewRegeneration(
                repoPath: repoPath,
                operationID: session.operationID
            )
            coordinator.publish(committed, repoPath: repoPath, initiatorID: windowID)
            phase = .idle
            await refreshLanguageStatus()
        } catch {
            phase = await .failed(mappedError(error))
            await refreshSharedSession(operationID: session.operationID)
        }
    }

    func cancel() async {
        guard canInteractWithSharedOperation,
              let session = sharedOperation?.session,
              session.cancellationAllowed
        else { return }
        phase = .canceling
        do {
            let canceled = try await bridge.cancelOverviewRegeneration(
                repoPath: repoPath,
                operationID: session.operationID
            )
            coordinator.publish(canceled, repoPath: repoPath, initiatorID: windowID)
            phase = .idle
            await refreshLanguageStatus()
        } catch {
            phase = await .failed(mappedError(error))
            await refreshSharedSession(operationID: session.operationID)
        }
    }

    func recoverSafely() async {
        guard canInteractWithSharedOperation,
              let session = sharedOperation?.session,
              session.status == .rollbackRequired
        else { return }
        phase = .recovering
        do {
            let recovered = try await bridge.resumeOverviewRegeneration(
                repoPath: repoPath,
                operationID: session.operationID
            )
            coordinator.publish(recovered, repoPath: repoPath, initiatorID: windowID)
            phase = .idle
            await refreshLanguageStatus()
        } catch {
            phase = await .failed(mappedError(error))
            await refreshSharedSession(operationID: session.operationID)
        }
    }

    func dismissTerminalOperation() {
        guard let status = sharedOperation?.session.status,
              [.completed, .rolledBack, .failed, .canceled].contains(status)
        else { return }
        coordinator.clear(repoPath: repoPath)
    }

    private func refreshSharedSession(operationID: String) async {
        guard let refreshed = try? await bridge.overviewRegeneration(
            repoPath: repoPath,
            operationID: operationID
        ) else { return }
        coordinator.publish(refreshed, repoPath: repoPath, initiatorID: nil)
    }

    private func refreshLanguageStatus() async {
        guard let concreteContentLocale else { return }
        languageStatusGeneration &+= 1
        let requestGeneration = languageStatusGeneration
        let requestLocale = concreteContentLocale
        do {
            let status = try await bridge.overviewLanguageStatus(
                repoPath: repoPath,
                contentLocale: requestLocale
            )
            guard requestGeneration == languageStatusGeneration,
                  self.concreteContentLocale == requestLocale,
                  !Task.isCancelled
            else { return }
            languageStatus = status
        } catch {
            guard requestGeneration == languageStatusGeneration,
                  self.concreteContentLocale == requestLocale,
                  !Task.isCancelled
            else { return }
            languageStatus = nil
        }
    }

    private func mappedError(_ error: Error) async -> RepositoryOverviewRegenerationError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return RepositoryOverviewRegenerationError(
                message: mapping.userMessageDescriptor,
                recovery: mapping.recoveryMessage(fallback: mapping.userMessageDescriptor)
            )
        }
        return RepositoryOverviewRegenerationError(
            message: L10n.message(
                "settings.repository.overview.error",
                technicalDetail: error.localizedDescription
            ),
            recovery: L10n.message("settings.repository.overview.errorRecovery")
        )
    }
}
