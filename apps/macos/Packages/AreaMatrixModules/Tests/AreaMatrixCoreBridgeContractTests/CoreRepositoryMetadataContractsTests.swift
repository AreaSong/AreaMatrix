import AreaMatrixCoreBridgeContract
import XCTest

final class CoreRepositoryMetadataContractsTests: XCTestCase {
    func testMetadataCapabilityCanBeImplementedWithoutGeneratedBindings() async throws {
        let expected = ExistingRepositoryMetadataSnapshot(
            schemaVersion: 3,
            lastOpenedAt: 42,
            configuredRepoPath: "/tmp/library"
        )
        let reader: any ExistingRepositoryMetadataReading = MetadataReader(snapshot: expected)

        let actual = try await reader.metadata(repoPath: "/tmp/library")

        XCTAssertEqual(actual, expected)
    }
}

private struct MetadataReader: ExistingRepositoryMetadataReading {
    let snapshot: ExistingRepositoryMetadataSnapshot

    func metadata(repoPath _: String) async throws -> ExistingRepositoryMetadataSnapshot {
        snapshot
    }
}
