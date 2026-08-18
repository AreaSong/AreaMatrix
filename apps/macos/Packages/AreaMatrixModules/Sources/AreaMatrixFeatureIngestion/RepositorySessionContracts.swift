import Foundation
import Observation

public struct RepositoryIdentity: Equatable, Hashable, Sendable {
    public let standardizedPath: String

    public init(repoPath: String) {
        standardizedPath = URL(fileURLWithPath: repoPath, isDirectory: true)
            .standardizedFileURL
            .path
    }
}

public struct RepositoryAccessSnapshot: Equatable, Sendable {
    public let isReadOnly: Bool
    public let writeLockedFileIDs: Set<Int64>

    public init(isReadOnly: Bool, writeLockedFileIDs: Set<Int64>) {
        self.isReadOnly = isReadOnly
        self.writeLockedFileIDs = writeLockedFileIDs
    }
}

public struct RepositoryOperationContext: Equatable, Sendable {
    public let identity: RepositoryIdentity
    public let repoPath: String
    public let expectedRevision: Int64
    public let access: RepositoryAccessSnapshot

    public init(
        identity: RepositoryIdentity,
        repoPath: String,
        expectedRevision: Int64,
        access: RepositoryAccessSnapshot
    ) {
        self.identity = identity
        self.repoPath = repoPath
        self.expectedRevision = expectedRevision
        self.access = access
    }
}

public enum RepositorySessionRefreshError: Error, Equatable, Sendable {
    case repositoryIdentityMismatch(expected: RepositoryIdentity, actual: RepositoryIdentity)
}

@MainActor
@Observable
public final class RepositorySession {
    public let identity: RepositoryIdentity
    public private(set) var repoPath: String
    public private(set) var revision: Int64
    public private(set) var access: RepositoryAccessSnapshot

    public init(
        repoPath: String,
        revision: Int64,
        access: RepositoryAccessSnapshot
    ) {
        identity = RepositoryIdentity(repoPath: repoPath)
        self.repoPath = repoPath
        self.revision = revision
        self.access = access
    }

    public func makeOperationContext() -> RepositoryOperationContext {
        RepositoryOperationContext(
            identity: identity,
            repoPath: repoPath,
            expectedRevision: revision,
            access: access
        )
    }

    public func refresh(
        repoPath: String,
        revision: Int64,
        access: RepositoryAccessSnapshot
    ) throws {
        let refreshedIdentity = RepositoryIdentity(repoPath: repoPath)
        guard refreshedIdentity == identity else {
            throw RepositorySessionRefreshError.repositoryIdentityMismatch(
                expected: identity,
                actual: refreshedIdentity
            )
        }
        self.repoPath = repoPath
        self.revision = revision
        self.access = access
    }
}
