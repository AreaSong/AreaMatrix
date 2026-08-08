@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreCommandIndexContractTests: XCTestCase {
    func testCommandIndexRequestPreservesSelectionAndQuery() {
        let request = CommandIndexRequestSnapshot(
            query: "report",
            selectedFileIDs: [3, 8],
            currentPath: "Work",
            includeFileCandidates: true
        )

        XCTAssertEqual(request.query, "report")
        XCTAssertEqual(request.selectedFileIDs, [3, 8])
        XCTAssertEqual(request.currentPath, "Work")
        XCTAssertTrue(request.includeFileCandidates)
    }

    func testCommandTargetWireValuesAreStable() {
        XCTAssertEqual(CommandTargetGroupSnapshot.currentSelection.rawValue, "Current Selection")
        XCTAssertEqual(CommandTargetKindSnapshot.fileCandidate.rawValue, "File Candidate")
        XCTAssertEqual(CommandTargetActionSnapshot.openConfirmation.rawValue, "Open Confirmation")
    }

    func testCommandIndexCapabilityCanBeImplementedWithoutGeneratedBindings() async throws {
        let indexer = CommandIndexContractDouble()
        let index = try await indexer.listCommandTargets(
            repoPath: "/tmp/repository",
            context: CommandIndexRequestSnapshot(
                query: nil,
                selectedFileIDs: [],
                currentPath: nil,
                includeFileCandidates: false
            )
        )

        XCTAssertEqual(index.commands.count, 1)
        XCTAssertEqual(index.commands[0].action, .openSearch)
    }
}

private struct CommandIndexContractDouble: CoreCommandIndexing {
    func listCommandTargets(
        repoPath _: String,
        context _: CommandIndexRequestSnapshot
    ) async throws -> CoreCommandIndexSnapshot {
        CoreCommandIndexSnapshot(
            commands: [
                CoreCommandTargetSnapshot(
                    id: "search",
                    title: "Search",
                    subtitle: nil,
                    group: .commands,
                    kind: .command,
                    action: .openSearch,
                    route: nil,
                    shortcut: nil,
                    disabled: false,
                    disabledReason: nil,
                    requiresConfirmation: false,
                    fileID: nil,
                    savedSearchID: nil
                )
            ],
            navigationTargets: [],
            currentSelectionTargets: [],
            recentTargets: [],
            smartLists: [],
            fileCandidates: [],
            generatedAt: 1
        )
    }
}
