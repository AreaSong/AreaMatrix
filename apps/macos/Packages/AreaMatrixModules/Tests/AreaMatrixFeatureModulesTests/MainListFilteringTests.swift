import AreaMatrixCoreBridgeContract
import AreaMatrixFeatureLibrary
import XCTest

final class MainListFilteringTests: XCTestCase {
    private struct Item: Equatable {
        let name: String
        let scope: String
    }

    func testVisibleItemsMatchesDisplayNameWithinSelectedScope() {
        let items = [
            Item(name: "Résumé.pdf", scope: "docs"),
            Item(name: "research.md", scope: "docs"),
            Item(name: "resume.txt", scope: "archive")
        ]

        let result = MainListFiltering.visibleItems(
            from: items,
            filterText: " resume ",
            isInSelectedScope: { $0.scope == "docs" },
            displayName: \Item.name
        )

        XCTAssertEqual(result, [items[0]])
    }

    func testEmptyFilterStillAppliesSelectedScope() {
        let items = [
            Item(name: "one", scope: "docs"),
            Item(name: "two", scope: "archive")
        ]

        let result = MainListFiltering.visibleItems(
            from: items,
            filterText: "  ",
            isInSelectedScope: { $0.scope == "docs" },
            displayName: \Item.name
        )

        XCTAssertEqual(result, [items[0]])
    }
}

final class FileEntryDisplayTests: XCTestCase {
    func testDisplayProjectionsRemainDeterministic() {
        let file = FileEntrySnapshot(
            id: 1,
            path: "Documents/Reports/summary.md",
            originalName: "summary.md",
            currentName: "summary.md",
            category: "Documents",
            sizeBytes: 1024,
            hashSha256: "hash",
            storageMode: "copy",
            origin: "test",
            sourcePath: nil,
            importedAt: 0,
            updatedAt: 0
        )

        XCTAssertEqual(FileEntryDisplay.categoryPath(for: file), "Documents/Reports")
        XCTAssertEqual(FileEntryDisplay.size(for: file), "1 KB")
        XCTAssertFalse(FileEntryDisplay.importedAt(for: file).isEmpty)
        XCTAssertEqual(FileEntryDisplay.importedAt(for: file), FileEntryDisplay.updatedAt(for: file))
    }
}

final class MainListProjectionTests: XCTestCase {
    func testProjectionKeepsSearchResultsAndLocalizedCountInputSeparate() {
        let files = [
            FileEntrySnapshot(
                id: 1,
                path: "inbox/a.md",
                originalName: "a.md",
                currentName: "a.md",
                category: "inbox",
                sizeBytes: 1,
                hashSha256: "a",
                storageMode: "copy",
                origin: "test",
                sourcePath: nil,
                importedAt: 0,
                updatedAt: 0
            )
        ]
        let projection = MainListProjection.make(
            files: files,
            filterText: "a",
            isInSelectedScope: { $0.category == "inbox" },
            sortOrder: [],
            search: MainListProjection.SearchContext(isActive: false, resultCount: nil)
        )

        XCTAssertEqual(projection.visibleFiles, files)
        XCTAssertEqual(projection.resultCount, 1)
        XCTAssertFalse(projection.isSearchActive)
    }
}
