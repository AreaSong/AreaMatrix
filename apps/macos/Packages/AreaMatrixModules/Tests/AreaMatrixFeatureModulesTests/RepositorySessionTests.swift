import AreaMatrixFeatureIngestion
import XCTest

@MainActor
final class RepositorySessionTests: XCTestCase {
    func testIdentityNormalizesRepositoryPath() {
        let session = RepositorySession(
            repoPath: "/tmp/AreaMatrix/../Repository",
            revision: 7,
            access: RepositoryAccessSnapshot(isReadOnly: false, writeLockedFileIDs: [11])
        )

        XCTAssertEqual(session.identity.standardizedPath, "/tmp/Repository")
        XCTAssertEqual(session.repoPath, "/tmp/AreaMatrix/../Repository")
    }

    func testOperationContextReflectsCurrentSessionState() throws {
        let session = RepositorySession(
            repoPath: "/tmp/Repository",
            revision: 7,
            access: RepositoryAccessSnapshot(isReadOnly: false, writeLockedFileIDs: [11])
        )

        try session.refresh(
            repoPath: "/tmp/Repository/.",
            revision: 8,
            access: RepositoryAccessSnapshot(isReadOnly: true, writeLockedFileIDs: [12, 13])
        )

        XCTAssertEqual(
            session.makeOperationContext(),
            RepositoryOperationContext(
                identity: RepositoryIdentity(repoPath: "/tmp/Repository"),
                repoPath: "/tmp/Repository/.",
                expectedRevision: 8,
                access: RepositoryAccessSnapshot(isReadOnly: true, writeLockedFileIDs: [12, 13])
            )
        )
    }

    func testRefreshUpdatesSameRepository() throws {
        let session = RepositorySession(
            repoPath: "/tmp/Repository",
            revision: 7,
            access: RepositoryAccessSnapshot(isReadOnly: false, writeLockedFileIDs: [])
        )

        try session.refresh(
            repoPath: "/tmp/Repository/.",
            revision: 9,
            access: RepositoryAccessSnapshot(isReadOnly: true, writeLockedFileIDs: [21])
        )

        XCTAssertEqual(session.repoPath, "/tmp/Repository/.")
        XCTAssertEqual(session.revision, 9)
        XCTAssertEqual(session.access, RepositoryAccessSnapshot(isReadOnly: true, writeLockedFileIDs: [21]))
    }

    func testRefreshRejectsAnotherRepositoryWithoutMutation() {
        let initialAccess = RepositoryAccessSnapshot(isReadOnly: false, writeLockedFileIDs: [11])
        let session = RepositorySession(repoPath: "/tmp/Repository", revision: 7, access: initialAccess)

        XCTAssertThrowsError(
            try session.refresh(
                repoPath: "/tmp/AnotherRepository",
                revision: 9,
                access: RepositoryAccessSnapshot(isReadOnly: true, writeLockedFileIDs: [])
            )
        ) { error in
            XCTAssertEqual(
                error as? RepositorySessionRefreshError,
                .repositoryIdentityMismatch(
                    expected: RepositoryIdentity(repoPath: "/tmp/Repository"),
                    actual: RepositoryIdentity(repoPath: "/tmp/AnotherRepository")
                )
            )
        }
        XCTAssertEqual(session.repoPath, "/tmp/Repository")
        XCTAssertEqual(session.revision, 7)
        XCTAssertEqual(session.access, initialAccess)
    }
}
