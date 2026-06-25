import Combine
import Foundation

enum SyncConflictEntryState: Equatable {
    case notLoaded
    case loading
    case empty
    case loaded(SyncConflictEntrySnapshot)
    case failed(CoreErrorMappingSnapshot)

    var snapshot: SyncConflictEntrySnapshot? {
        guard case let .loaded(snapshot) = self else { return nil }
        return snapshot
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct SyncConflictEntrySnapshot: Equatable {
    var conflicts: [SyncConflictSnapshot]

    var count: Int {
        conflicts.count
    }

    var firstReviewableConflict: SyncConflictSnapshot? {
        conflicts.first { $0.normalizedConflictID != nil }
    }

    var latestDetectedAt: Int64? {
        conflicts.compactMap(\.detectedAt).max()
    }

    var latestDetectedDisplay: String {
        guard let latestDetectedAt else { return "Unknown" }
        return Date(timeIntervalSince1970: TimeInterval(latestDetectedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var typeSummary: String {
        let names = conflicts.map(\.conflictType.displayName)
        let unique = Array(NSOrderedSet(array: names)) as? [String] ?? names
        return unique.prefix(3).joined(separator: ", ")
    }

    var severitySummary: String {
        if conflicts.contains(where: { $0.severity == .high }) { return "High" }
        if conflicts.contains(where: { $0.severity == .medium }) { return "Medium" }
        return "Low"
    }
}

@MainActor
final class SyncConflictEntryModel: ObservableObject {
    @Published private(set) var state: SyncConflictEntryState = .notLoaded
    @Published private(set) var isBannerDismissed = false

    let repoPath: String
    private let conflictDetector: any CoreSyncConflictDetecting
    private let errorMapper: any CoreErrorMapping
    private var loadGeneration = 0

    init(
        repoPath: String,
        conflictDetector: any CoreSyncConflictDetecting = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.conflictDetector = conflictDetector
        self.errorMapper = errorMapper
    }

    var snapshot: SyncConflictEntrySnapshot? {
        state.snapshot
    }

    var isLoading: Bool {
        state.isLoading
    }

    var isBannerVisible: Bool {
        !isBannerDismissed && snapshot?.count ?? 0 > 0
    }

    func loadIfNeeded() async {
        guard case .notLoaded = state else { return }
        await load()
    }

    func refresh() async {
        isBannerDismissed = false
        await load()
    }

    func dismissBanner() {
        isBannerDismissed = true
    }

    func reviewRoute(for conflict: SyncConflictSnapshot) -> SyncConflictReviewRoute {
        SyncConflictReviewRoute(
            repoPath: repoPath,
            conflictID: conflict.normalizedConflictID,
            primaryPath: conflict.primaryPath
        )
    }

    func detailConflict(for file: FileEntrySnapshot?) -> SyncConflictSnapshot? {
        guard let file else { return nil }
        return snapshot?.conflicts.first { $0.matchesSyncConflictEntry(file: file) }
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading

        do {
            let conflicts = try await conflictDetector.detectSyncConflicts(repoPath: repoPath)
            guard generation == loadGeneration else { return }
            let reviewable = conflicts.filter { $0.status == .needsReview }
            let snapshot = SyncConflictEntrySnapshot(conflicts: sortConflicts(reviewable))
            state = snapshot.conflicts.isEmpty ? .empty : .loaded(snapshot)
        } catch {
            guard generation == loadGeneration else { return }
            state = await .failed(mapError(error))
        }
    }

    private func sortConflicts(_ conflicts: [SyncConflictSnapshot]) -> [SyncConflictSnapshot] {
        conflicts.sorted { lhs, rhs in
            if lhs.severity.sortRank != rhs.severity.sortRank {
                return lhs.severity.sortRank > rhs.severity.sortRank
            }
            return (lhs.detectedAt ?? 0) > (rhs.detectedAt ?? 0)
        }
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}

extension SyncConflictSnapshot {
    var normalizedConflictID: String? {
        let trimmed = conflictID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func matchesSyncConflictEntry(file: FileEntrySnapshot) -> Bool {
        primaryPath == file.path ||
            affectedFiles.contains { affected in
                affected.path == file.path || affected.fileID == file.id
            }
    }
}

private extension SyncConflictSeveritySnapshot {
    var sortRank: Int {
        switch self {
        case .high:
            3
        case .medium:
            2
        case .low:
            1
        }
    }
}
