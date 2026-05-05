import XCTest
@testable import AreaMatrix

final class MainListIntegrationFilterTests: XCTestCase {
    func testCurrentListFilterMatchesLoadedFileNamesOnly() {
        let files = [
            FileEntrySnapshot.integrationFilterFixture(
                id: 1,
                path: "docs/contracts/customer.pdf",
                category: "docs",
                currentName: "customer.pdf"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 2,
                path: "docs/references/research.md",
                category: "docs",
                currentName: "research.md"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 3,
                path: "docs/contracts/budget.xlsx",
                category: "docs",
                currentName: "budget.xlsx"
            ),
        ]
        let row = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
            .sidebarRow(id: "docs/contracts")

        guard let row else {
            return XCTFail("expected docs/contracts sidebar row")
        }

        let result = MainListVisibleFileFiltering.visibleFiles(
            from: files,
            sidebarRow: row,
            filterText: "customer"
        )

        XCTAssertEqual(result.map(\.id), [1])
    }

    func testCurrentListFilterDoesNotSearchAcrossCategoryOrPathFields() {
        let files = [
            FileEntrySnapshot.integrationFilterFixture(
                id: 1,
                path: "docs/contracts/customer.pdf",
                category: "docs",
                currentName: "customer.pdf"
            ),
            FileEntrySnapshot.integrationFilterFixture(
                id: 2,
                path: "docs/references/research.md",
                category: "docs",
                currentName: "research.md"
            ),
        ]
        let row = RepositoryTreeNodeSnapshot.integrationFilterFixtureTree()
            .sidebarRow(id: "docs")

        guard let row else {
            return XCTFail("expected docs sidebar row")
        }

        let result = MainListVisibleFileFiltering.visibleFiles(
            from: files,
            sidebarRow: row,
            filterText: "contracts"
        )

        XCTAssertEqual(result, [])
    }
}

private extension RepositoryTreeNodeSnapshot {
    static func integrationFilterFixtureTree() -> RepositoryTreeNodeSnapshot {
        RepositoryTreeNodeSnapshot(
            slug: "__root__",
            displayName: "Repository",
            kind: "RepositoryRoot",
            relativePath: "",
            fileCount: 0,
            depth: 0,
            children: [
                RepositoryTreeNodeSnapshot(
                    slug: "docs",
                    displayName: "docs",
                    fileCount: 0,
                    children: [
                        RepositoryTreeNodeSnapshot(
                            slug: "contracts",
                            displayName: "contracts",
                            kind: "Subdir",
                            relativePath: "docs/contracts",
                            fileCount: 2,
                            depth: 2,
                            children: []
                        ),
                        RepositoryTreeNodeSnapshot(
                            slug: "references",
                            displayName: "references",
                            kind: "Subdir",
                            relativePath: "docs/references",
                            fileCount: 1,
                            depth: 2,
                            children: []
                        ),
                    ]
                ),
            ]
        )
    }
}

private extension FileEntrySnapshot {
    static func integrationFilterFixture(
        id: Int64,
        path: String,
        category: String,
        currentName: String
    ) -> FileEntrySnapshot {
        FileEntrySnapshot(
            id: id,
            path: path,
            originalName: currentName,
            currentName: currentName,
            category: category,
            sizeBytes: 128,
            hashSha256: "integration-filter-\(id)",
            storageMode: "Copied",
            origin: "Imported",
            sourcePath: nil,
            importedAt: 1_700_000_000 - id,
            updatedAt: 1_700_000_000
        )
    }
}
