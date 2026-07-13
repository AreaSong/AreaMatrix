@testable import AreaMatrix
import XCTest

struct NoopRepositoryIgnoreRulesManager: RepositoryIgnoreRulesManaging {
    @MainActor
    func openIgnoreRules(repoPath _: String) throws {}

    @MainActor
    func createDefaultIgnoreRules(repoPath _: String) throws {}
}

struct StaticRootOverviewFileInspector: RootOverviewFileInspecting {
    let status: RootOverviewFileStatus

    func status(repoPath _: String) -> RootOverviewFileStatus {
        status
    }
}

@MainActor
final class RecordingRepositoryIgnoreRulesManager: RepositoryIgnoreRulesManaging {
    enum OpenScenario {
        case success
        case missingThenSuccess
    }

    private let openScenario: OpenScenario
    private var openAttempts = 0
    private var openedPaths: [String] = []
    private var createdPaths: [String] = []

    init(openScenario: OpenScenario = .success) {
        self.openScenario = openScenario
    }

    func openIgnoreRules(repoPath: String) throws {
        openedPaths.append(repoPath)
        if openScenario == .missingThenSuccess, openAttempts == 0 {
            openAttempts += 1
            throw RepositoryIgnoreRulesError.ignoreRulesMissing
        }
        openAttempts += 1
    }

    func createDefaultIgnoreRules(repoPath: String) throws {
        createdPaths.append(repoPath)
    }

    func assertOpenedPaths(
        _ expectedPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(openedPaths, expectedPaths, file: file, line: line)
    }

    func assertCreatedPaths(
        _ expectedPaths: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(createdPaths, expectedPaths, file: file, line: line)
    }
}
