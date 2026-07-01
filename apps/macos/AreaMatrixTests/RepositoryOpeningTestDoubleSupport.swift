@testable import AreaMatrix

actor RecordingRepositoryOpener: CoreEmptyRepositoryOpening {
    private let result: Swift.Result<RepositoryOpeningResult, Error>
    private var repoPaths: [String] = []
    private var configuredRepoPaths: [String] = []
    private var emptyRepoPaths: [String] = []
    private var adoptedRepoPaths: [String] = []

    init(result: Swift.Result<RepositoryOpeningResult, Error>) {
        self.result = result
    }

    init(opening: RepositoryOpeningResult) {
        result = .success(opening)
    }

    init(error: Error) {
        result = .failure(error)
    }

    func openConfiguredRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        repoPaths.append(repoPath)
        configuredRepoPaths.append(repoPath)
        return try result.get()
    }

    func openEmptyRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        repoPaths.append(repoPath)
        emptyRepoPaths.append(repoPath)
        return try result.get()
    }

    func openAdoptedRepository(repoPath: String) async throws -> RepositoryOpeningResult {
        repoPaths.append(repoPath)
        adoptedRepoPaths.append(repoPath)
        return try result.get()
    }

    func requestedRepoPaths() -> [String] {
        repoPaths
    }

    func requestedConfiguredRepoPaths() -> [String] {
        configuredRepoPaths
    }

    func requestedEmptyRepoPaths() -> [String] {
        emptyRepoPaths
    }

    func requestedAdoptedRepoPaths() -> [String] {
        adoptedRepoPaths
    }
}
