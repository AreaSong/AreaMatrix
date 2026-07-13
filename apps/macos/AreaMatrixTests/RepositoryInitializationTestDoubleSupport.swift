@testable import AreaMatrix
import XCTest

actor RecordingRepositoryInitializer: CoreRepositoryInitializing, RepositoryInitializationPathRecording {
    typealias InitializationResult = Swift.Result<Void, Error>

    private var createQueue: VoidResultQueue
    private var adoptQueue: VoidResultQueue
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []

    init(result: InitializationResult = .success(())) {
        createQueue = VoidResultQueue(result: result)
        adoptQueue = VoidResultQueue(result: result)
    }

    init(error: Error) {
        createQueue = VoidResultQueue(result: .failure(error))
        adoptQueue = VoidResultQueue(result: .failure(error))
    }

    init(firstError: Error) {
        createQueue = VoidResultQueue(failureThenSuccess: firstError)
        adoptQueue = VoidResultQueue(failureThenSuccess: firstError)
    }

    init(createResults: [InitializationResult], adoptResults: [InitializationResult]) {
        createQueue = VoidResultQueue(results: createResults)
        adoptQueue = VoidResultQueue(results: adoptResults)
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
        try createQueue.next().get()
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
        try adoptQueue.next().get()
    }

    var createdRepoPathsForAssertions: [String] {
        createdPaths
    }

    var adoptedRepoPathsForAssertions: [String] {
        adoptedPaths
    }
}

actor PausingRepositoryInitializer: CoreRepositoryInitializing, RepositoryInitializationPathRecording {
    private let delayNanoseconds: UInt64
    private var createdPaths: [String] = []
    private var adoptedPaths: [String] = []
    private var didStart = false

    init(delayNanoseconds: UInt64 = 500_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func initializeEmptyRepository(repoPath: String) async throws {
        createdPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    func adoptExistingRepository(repoPath: String) async throws {
        adoptedPaths.append(repoPath)
        didStart = true
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    func waitUntilStarted() async {
        _ = await waitForActorTestValue(
            on: self,
            failureMessage: { "Timed out waiting for repository initialization to start" },
            value: {
                didStart ? true : nil
            }
        )
    }

    var createdRepoPathsForAssertions: [String] {
        createdPaths
    }

    var adoptedRepoPathsForAssertions: [String] {
        adoptedPaths
    }
}

protocol RepositoryInitializationPathRecording: Actor {
    var createdRepoPathsForAssertions: [String] { get }
    var adoptedRepoPathsForAssertions: [String] { get }
}

extension RepositoryInitializationPathRecording {
    func assertCreatedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(createdRepoPathsForAssertions, expectedRepoPaths, file: file, line: line)
    }

    func assertAdoptedRepoPaths(
        _ expectedRepoPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(adoptedRepoPathsForAssertions, expectedRepoPaths, file: file, line: line)
    }
}
