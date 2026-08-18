@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreFileReadingContractTests: XCTestCase {
    func testCurrentCategoryBuildsStableFirstPageFilter() {
        XCTAssertEqual(
            FileFilterSnapshot.currentCategory("inbox"),
            FileFilterSnapshot(
                category: "inbox",
                includeDeleted: false,
                importedAfter: nil,
                importedBefore: nil,
                limit: 50,
                offset: 0
            )
        )
    }

    func testFileEntryPreservesAvailabilityAndCommitState() {
        let entry = FileEntrySnapshot(
            id: 7,
            path: "inbox/note.md",
            originalName: "note.md",
            currentName: "note.md",
            category: "inbox",
            sizeBytes: 12,
            hashSha256: "hash",
            storageMode: "Indexed",
            origin: "Adopted",
            sourcePath: nil,
            importedAt: 10,
            updatedAt: 11,
            availability: .iCloudPlaceholder,
            importCommitState: .sourceRetained
        )

        XCTAssertEqual(entry.availability, .iCloudPlaceholder)
        XCTAssertTrue(entry.importCommitState.isDegraded)
    }

    func testFileReadCapabilitiesCanBeImplementedWithoutGeneratedBindings() async throws {
        let reader = FileReaderDouble()
        let files = try await reader.listFiles(repoPath: "/tmp/repository", filter: .currentCategory(nil))
        let detail = try await reader.getFile(repoPath: "/tmp/repository", fileID: 7)

        XCTAssertEqual(files, [detail])
    }
}

private struct FileReaderDouble: CoreFileListing, CoreFileDetailing {
    func listFiles(repoPath _: String, filter _: FileFilterSnapshot) async throws -> [FileEntrySnapshot] {
        [entry]
    }

    func getFile(repoPath _: String, fileID _: Int64) async throws -> FileEntrySnapshot {
        entry
    }

    private var entry: FileEntrySnapshot {
        FileEntrySnapshot(
            id: 7,
            path: "inbox/note.md",
            originalName: "note.md",
            currentName: "note.md",
            category: "inbox",
            sizeBytes: 12,
            hashSha256: "hash",
            storageMode: "Indexed",
            origin: "Adopted",
            sourcePath: nil,
            importedAt: 10,
            updatedAt: 11
        )
    }
}
