import Combine
import Foundation

enum ICloudConflictListState: Equatable, Sendable {
    case notLoaded
    case loading
    case loaded([ICloudConflictPairSnapshot])
    case failed(CoreErrorMappingSnapshot)

    var conflicts: [ICloudConflictPairSnapshot] {
        guard case .loaded(let conflicts) = self else { return [] }
        return conflicts
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum ICloudConflictListRevealState: Equatable, Sendable {
    case idle
    case revealed(String)
    case failed(String)
}

@MainActor
final class ICloudConflictListModel: ObservableObject {
    @Published private(set) var state: ICloudConflictListState = .notLoaded
    @Published private(set) var revealState: ICloudConflictListRevealState = .idle

    let repoPath: String
    private let conflictLister: any CoreICloudConflictListing
    private let errorMapper: any CoreErrorMapping
    private let repositoryFinderOpener: any RepositoryFinderOpening
    private let fileRevealer: any RepositoryFileRevealing
    private var loadGeneration = 0

    init(
        repoPath: String,
        conflictLister: any CoreICloudConflictListing = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge(),
        repositoryFinderOpener: any RepositoryFinderOpening = NSWorkspaceRepositoryFinderOpener(),
        fileRevealer: any RepositoryFileRevealing = NSWorkspaceRepositoryFileRevealer()
    ) {
        self.repoPath = repoPath
        self.conflictLister = conflictLister
        self.errorMapper = errorMapper
        self.repositoryFinderOpener = repositoryFinderOpener
        self.fileRevealer = fileRevealer
    }

    var conflicts: [ICloudConflictPairSnapshot] { state.conflicts }
    var isLoading: Bool { state.isLoading }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading
        revealState = .idle

        do {
            let conflicts = try await conflictLister.listICloudConflicts(repoPath: repoPath)
            guard generation == loadGeneration else { return }
            state = .loaded(conflicts)
        } catch {
            guard generation == loadGeneration else { return }
            state = .failed(await mapError(error))
        }
    }

    func refresh() async {
        await load()
    }

    func revealRepositoryInFinder() {
        revealState = .idle
        do {
            try repositoryFinderOpener.openRepositoryInFinder(repoPath: repoPath)
            revealState = .revealed("Repository folder revealed in Finder.")
        } catch {
            revealState = .failed("Repository folder cannot be revealed.")
        }
    }

    func revealConflict(_ conflict: ICloudConflictPairSnapshot) {
        revealState = .idle
        do {
            try fileRevealer.revealFile(repoPath: repoPath, relativePath: conflict.conflictedCopyPath)
            revealState = .revealed("Conflict copy revealed in Finder.")
        } catch {
            revealState = .failed("Conflict copy cannot be revealed.")
        }
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}
