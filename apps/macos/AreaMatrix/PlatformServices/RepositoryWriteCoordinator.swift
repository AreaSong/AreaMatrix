import Foundation

actor RepositoryWriteCoordinator {
    static let shared = RepositoryWriteCoordinator()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var activeRepositories: Set<String> = []
    private var waitersByRepository: [String: [Waiter]] = [:]

    func withWriteAccess<Value>(
        repoPath: String,
        operation: () async throws -> Value
    ) async throws -> Value {
        let repositoryKey = Self.repositoryKey(repoPath)
        let waiterID = UUID()

        try await withTaskCancellationHandler {
            try await acquire(repositoryKey: repositoryKey, waiterID: waiterID)
        } onCancel: {
            Task { await self.cancelWaiter(repositoryKey: repositoryKey, waiterID: waiterID) }
        }

        if Task.isCancelled {
            release(repositoryKey: repositoryKey)
            throw CancellationError()
        }

        do {
            let value = try await operation()
            release(repositoryKey: repositoryKey)
            return value
        } catch {
            release(repositoryKey: repositoryKey)
            throw error
        }
    }

    private func acquire(repositoryKey: String, waiterID: UUID) async throws {
        try Task.checkCancellation()
        guard activeRepositories.contains(repositoryKey) else {
            activeRepositories.insert(repositoryKey)
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            waitersByRepository[repositoryKey, default: []].append(Waiter(
                id: waiterID,
                continuation: continuation
            ))
        }
    }

    private func cancelWaiter(repositoryKey: String, waiterID: UUID) {
        guard var waiters = waitersByRepository[repositoryKey],
              let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        waitersByRepository[repositoryKey] = waiters.isEmpty ? nil : waiters
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func release(repositoryKey: String) {
        guard var waiters = waitersByRepository[repositoryKey], !waiters.isEmpty else {
            activeRepositories.remove(repositoryKey)
            waitersByRepository[repositoryKey] = nil
            return
        }

        let waiter = waiters.removeFirst()
        waitersByRepository[repositoryKey] = waiters.isEmpty ? nil : waiters
        waiter.continuation.resume()
    }

    private static func repositoryKey(_ repoPath: String) -> String {
        URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
    }
}
