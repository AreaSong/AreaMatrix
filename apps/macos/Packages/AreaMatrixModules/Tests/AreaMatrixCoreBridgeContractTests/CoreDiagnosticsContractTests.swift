@testable import AreaMatrixCoreBridgeContract
import XCTest

final class CoreDiagnosticsContractTests: XCTestCase {
    func testDiagnosticsSnapshotIsValueStableAndSendable() {
        let snapshot = DiagnosticsSnapshotSnapshot(
            snapshotPath: "/tmp/diagnostics.zip",
            createdAt: 42,
            warnings: ["warning"]
        )

        XCTAssertEqual(snapshot.snapshotPath, "/tmp/diagnostics.zip")
        XCTAssertEqual(snapshot.createdAt, 42)
        XCTAssertEqual(snapshot.warnings, ["warning"])
        XCTAssertEqual(snapshot, snapshot)
    }

    func testDiagnosticsCapabilityCanBeImplementedWithoutGeneratedBindings() async throws {
        let collector = DiagnosticsContractDouble()
        let snapshot = try await collector.createDiagnosticsSnapshot(repoPath: "/tmp/repository")

        XCTAssertEqual(snapshot.snapshotPath, "/tmp/diagnostics.zip")
        XCTAssertEqual(snapshot.createdAt, 1)
    }
}

private struct DiagnosticsContractDouble: CoreDiagnosticsCollecting {
    func createDiagnosticsSnapshot(repoPath _: String) async throws -> DiagnosticsSnapshotSnapshot {
        DiagnosticsSnapshotSnapshot(snapshotPath: "/tmp/diagnostics.zip", createdAt: 1, warnings: [])
    }
}
