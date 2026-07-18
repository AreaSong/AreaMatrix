import Foundation

protocol InFlightFileChangeTracking: Sendable {
    func mark(repoPath: String, relativePath: String) async
    func unmark(repoPath: String, relativePath: String) async
    func contains(repoPath: String, relativePath: String) async -> Bool
}

actor InFlightFileChangeTracker: InFlightFileChangeTracking {
    static let shared = InFlightFileChangeTracker()

    private struct Entry {
        var count: Int
        var expiresAt: Date
    }

    private var entries: [InFlightFileChangeKey: Entry] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 60) {
        self.ttl = ttl
    }

    func mark(repoPath: String, relativePath: String) async {
        let key = InFlightFileChangeKey(repoPath: repoPath, relativePath: relativePath)
        let expiresAt = Date().addingTimeInterval(ttl)
        if var entry = entries[key] {
            entry.count += 1
            entry.expiresAt = expiresAt
            entries[key] = entry
        } else {
            entries[key] = Entry(count: 1, expiresAt: expiresAt)
        }
    }

    func unmark(repoPath: String, relativePath: String) async {
        let key = InFlightFileChangeKey(repoPath: repoPath, relativePath: relativePath)
        guard var entry = entries[key] else { return }
        if entry.count <= 1 {
            entry.count = 0
            entry.expiresAt = Date().addingTimeInterval(ttl)
            entries[key] = entry
        } else {
            entry.count -= 1
            entry.expiresAt = Date().addingTimeInterval(ttl)
            entries[key] = entry
        }
    }

    func contains(repoPath: String, relativePath: String) async -> Bool {
        let key = InFlightFileChangeKey(repoPath: repoPath, relativePath: relativePath)
        guard let entry = entries[key] else { return false }
        guard entry.expiresAt > Date() else {
            entries.removeValue(forKey: key)
            return false
        }
        return true
    }
}

private struct InFlightFileChangeKey: Hashable {
    var repoPath: String
    var relativePath: String

    init(repoPath: String, relativePath: String) {
        self.repoPath = URL(fileURLWithPath: repoPath, isDirectory: true).standardizedFileURL.path
        self.relativePath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
