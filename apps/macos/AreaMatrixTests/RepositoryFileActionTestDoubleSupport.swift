@testable import AreaMatrix

@MainActor
final class RecordingRepositoryFinderOpener: RepositoryFinderOpening {
    private let result: Result<Void, Error>
    private(set) var repoPaths: [String] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openRepositoryInFinder(repoPath: String) throws {
        repoPaths.append(repoPath)
        try result.get()
    }
}

@MainActor
final class RecordingRepositoryFileRevealer: RepositoryFileRevealing {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private let result: Result<Void, Error>
    private(set) var requests: [Request] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func revealFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
        try result.get()
    }
}

@MainActor
final class RecordingRepositoryFileOpener: RepositoryFileOpening {
    struct Request: Equatable {
        var repoPath: String
        var relativePath: String
    }

    private let result: Result<Void, Error>
    private(set) var requests: [Request] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func openFile(repoPath: String, relativePath: String) throws {
        requests.append(Request(repoPath: repoPath, relativePath: relativePath))
        try result.get()
    }
}
