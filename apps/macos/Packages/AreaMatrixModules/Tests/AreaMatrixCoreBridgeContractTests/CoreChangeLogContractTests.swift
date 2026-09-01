@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreChangeLogContractTests: XCTestCase {
    func testChangeFilterFactoriesPreserveStableRequests() {
        XCTAssertEqual(ChangeFilterSnapshot.importResultRecent.action, "imported")
        XCTAssertEqual(ChangeFilterSnapshot.importResultRecent.limit, 100)
        XCTAssertEqual(ChangeFilterSnapshot.detailLog(fileID: 9).fileID, 9)
        XCTAssertNil(ChangeFilterSnapshot.detailLog(fileID: 9).action)
    }

    func testChangeLogEntryIsValueStableAndSendable() {
        let entry = ChangeLogEntrySnapshot(
            id: 1,
            fileID: 2,
            filename: "note.md",
            category: "work",
            action: "edited_note",
            detailJSON: "{}",
            occurredAt: 3
        )

        XCTAssertEqual(entry.id, 1)
        XCTAssertEqual(entry.fileID, 2)
        XCTAssertEqual(entry.filename, "note.md")
        XCTAssertEqual(entry, entry)
    }

    func testChangeLogCapabilityCanBeImplementedWithoutGeneratedBindings() async throws {
        let listing = ChangeLogContractDouble()
        let entries = try await listing.listChanges(repoPath: "/tmp/repository", filter: .detailLog(fileID: 7))

        XCTAssertEqual(entries.map(\.fileID), [7])
    }
}

private struct ChangeLogContractDouble: CoreChangeLogListing {
    func listChanges(repoPath _: String, filter: ChangeFilterSnapshot) async throws -> [ChangeLogEntrySnapshot] {
        [
            ChangeLogEntrySnapshot(
                id: 1,
                fileID: filter.fileID,
                filename: "fixture.md",
                category: "fixture",
                action: "edited_note",
                detailJSON: "{}",
                occurredAt: 1
            )
        ]
    }
}
