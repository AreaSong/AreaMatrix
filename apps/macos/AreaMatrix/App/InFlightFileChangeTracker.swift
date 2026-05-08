import Foundation

protocol InFlightFileChangeTracking: Sendable {
    func mark(repoPath: String, relativePath: String) async
    func unmark(repoPath: String, relativePath: String) async
    func contains(repoPath: String, relativePath: String) async -> Bool
}

actor InFlightFileChangeTracker: InFlightFileChangeTracking {
    static let shared = InFlightFileChangeTracker()

    private var counts: [InFlightFileChangeKey: Int] = [:]

    func mark(repoPath: String, relativePath: String) async {
        let key = InFlightFileChangeKey(repoPath: repoPath, relativePath: relativePath)
        counts[key, default: 0] += 1
    }

    func unmark(repoPath: String, relativePath: String) async {
        let key = InFlightFileChangeKey(repoPath: repoPath, relativePath: relativePath)
        guard let count = counts[key] else { return }
        if count <= 1 {
            counts.removeValue(forKey: key)
        } else {
            counts[key] = count - 1
        }
    }

    func contains(repoPath: String, relativePath: String) async -> Bool {
        counts[InFlightFileChangeKey(repoPath: repoPath, relativePath: relativePath)] != nil
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
