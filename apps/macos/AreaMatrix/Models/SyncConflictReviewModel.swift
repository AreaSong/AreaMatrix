import Combine
import Foundation

enum SyncConflictReviewState: Equatable {
    case notLoaded
    case loading
    case loaded(SyncConflictSnapshot)
    case empty
    case failed(CoreErrorMappingSnapshot)

    var conflict: SyncConflictSnapshot? {
        guard case let .loaded(conflict) = self else { return nil }
        return conflict
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

@MainActor
final class SyncConflictReviewModel: ObservableObject {
    @Published private(set) var state: SyncConflictReviewState = .notLoaded

    let repoPath: String
    let conflictID: String?
    let primaryPath: String?
    private let conflictDetector: any CoreSyncConflictDetecting
    private let errorMapper: any CoreErrorMapping
    private var loadGeneration = 0

    init(
        repoPath: String,
        conflictID: String? = nil,
        primaryPath: String? = nil,
        conflictDetector: any CoreSyncConflictDetecting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.conflictID = conflictID
        self.primaryPath = primaryPath
        self.conflictDetector = conflictDetector
        self.errorMapper = errorMapper
    }

    var conflict: SyncConflictSnapshot? {
        state.conflict
    }

    var isLoading: Bool {
        state.isLoading
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading

        do {
            let conflicts = try await conflictDetector.detectSyncConflicts(repoPath: repoPath)
            guard generation == loadGeneration else { return }
            state = selectedConflict(from: conflicts).map(SyncConflictReviewState.loaded) ?? .empty
        } catch {
            guard generation == loadGeneration else { return }
            state = await .failed(mapError(error))
        }
    }

    func refresh() async {
        await load()
    }

    private func selectedConflict(from conflicts: [SyncConflictSnapshot]) -> SyncConflictSnapshot? {
        let reviewableConflicts = conflicts.filter { $0.status == .needsReview }
        guard let conflictID else {
            guard let primaryPath = normalizedPrimaryPath else {
                return reviewableConflicts.first
            }
            return reviewableConflicts.first { $0.matches(path: primaryPath) }
        }
        return reviewableConflicts.first { $0.conflictID == conflictID }
    }

    private var normalizedPrimaryPath: String? {
        let trimmed = primaryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

struct SyncConflictReviewRoute: Equatable, Identifiable {
    var repoPath: String
    var conflictID: String?
    var primaryPath: String?

    var id: String {
        [repoPath, conflictID ?? "", primaryPath ?? ""].joined(separator: "|")
    }

    static func fileDetail(repoPath: String, file: FileEntrySnapshot) -> SyncConflictReviewRoute {
        SyncConflictReviewRoute(repoPath: repoPath, conflictID: nil, primaryPath: file.path)
    }
}

private extension SyncConflictSnapshot {
    func matches(path: String) -> Bool {
        primaryPath == path || affectedFiles.contains { $0.path == path }
    }
}
