import AreaMatrixCoreBridgeContract
import Foundation

typealias CoreFileListing = AreaMatrixCoreBridgeContract.CoreFileListing
typealias CoreFileDetailing = AreaMatrixCoreBridgeContract.CoreFileDetailing
typealias FileFilterSnapshot = AreaMatrixCoreBridgeContract.FileFilterSnapshot
typealias FileAvailabilitySnapshot = AreaMatrixCoreBridgeContract.FileAvailabilitySnapshot
typealias CoreImportCommitState = AreaMatrixCoreBridgeContract.CoreImportCommitState
typealias FileEntrySnapshot = AreaMatrixCoreBridgeContract.FileEntrySnapshot

extension CoreBridge: CoreFileListing, CoreFileDetailing {}

protocol CoreMissingFileRecovering: Sendable {
    func missingFileState(repoPath: String, fileID: Int64) async throws -> MissingFileStateSnapshot
    func relinkMissingFile(
        repoPath: String,
        fileID: Int64,
        newPath: String
    ) async throws -> MissingFileRecoveryReportSnapshot
}

extension CoreBridge: CoreMissingFileRecovering {
    func missingFileState(repoPath: String, fileID: Int64) async throws -> MissingFileStateSnapshot {
        try await Task.detached(priority: .userInitiated) {
            try MissingFileStateSnapshot(coreState: getMissingFileState(repoPath: repoPath, fileId: fileID))
        }.value
    }

    func relinkMissingFile(
        repoPath: String,
        fileID: Int64,
        newPath: String
    ) async throws -> MissingFileRecoveryReportSnapshot {
        try await Task.detached(priority: .userInitiated) {
            let request = MissingFileRelinkRequest(fileId: fileID, newPath: newPath, confirmed: true)
            let report = try relinkCoreMissingFile(repoPath: repoPath, request: request)
            return MissingFileRecoveryReportSnapshot(coreReport: report)
        }.value
    }
}

private func relinkCoreMissingFile(
    repoPath: String,
    request: MissingFileRelinkRequest
) throws -> MissingFileRecoveryReport {
    try relinkMissingFile(repoPath: repoPath, request: request)
}

struct MissingFileStateSnapshot: Equatable {
    var fileID: Int64
    var relativePath: String
    var lastKnownPath: String?
    var expectedHashSha256: String?
    var reason: MissingFileReasonSnapshot
    var canLocate: Bool
}

enum MissingFileReasonSnapshot: Equatable {
    case pathMissing
    case permissionDenied
    case cloudPlaceholder
    case externalVolumeDisconnected
    case unknown
}

struct MissingFileRecoveryReportSnapshot: Equatable {
    var fileID: Int64
    var status: MissingFileRecoveryStatusSnapshot
    var previousPath: String?
    var currentPath: String?
    var hashMatched: Bool
    var fileDeleted: Bool
    var message: String?
}

enum MissingFileRecoveryStatusSnapshot: Equatable {
    case missing
    case present
    case relinked
    case hashMismatch
    case recordRemoved
    case blocked
}

protocol FileAvailabilityChecking: Sendable {
    func availability(
        repoPath: String,
        relativePath: String,
        sourcePath: String?,
        coreStatus: FileAvailabilityStatus
    ) async -> FileAvailabilitySnapshot
}

struct LocalFileAvailabilityChecker: FileAvailabilityChecking {
    func availability(
        repoPath: String,
        relativePath: String,
        sourcePath: String?,
        coreStatus: FileAvailabilityStatus
    ) async -> FileAvailabilitySnapshot {
        FileAvailabilityResolver.availability(
            repoPath: repoPath,
            relativePath: relativePath,
            sourcePath: sourcePath,
            coreStatus: coreStatus
        )
    }
}

extension FileEntrySnapshot {
    var statusDisplay: String {
        switch availability {
        case .missing:
            L10n.string("Missing")
        case .iCloudPlaceholder:
            L10n.string("iCloud")
        case .available:
            if storageMode == "Indexed" {
                L10n.string("Index-only")
            } else {
                L10n.string("OK")
            }
        }
    }
}

extension FileFilter {
    init(_ snapshot: FileFilterSnapshot) {
        self.init(
            category: snapshot.category,
            includeDeleted: snapshot.includeDeleted,
            importedAfter: snapshot.importedAfter,
            importedBefore: snapshot.importedBefore,
            limit: snapshot.limit,
            offset: snapshot.offset
        )
    }
}

extension FileEntrySnapshot {
    init(coreEntry: FileEntry, availabilityChecker: (String, String?) -> FileAvailabilitySnapshot) {
        self.init(
            id: coreEntry.id,
            path: coreEntry.path,
            originalName: coreEntry.originalName,
            currentName: coreEntry.currentName,
            category: coreEntry.category,
            sizeBytes: coreEntry.sizeBytes,
            hashSha256: coreEntry.hashSha256,
            storageMode: coreEntry.storageMode.fileListDisplayName,
            origin: coreEntry.origin.fileListDisplayName,
            sourcePath: coreEntry.sourcePath,
            importedAt: coreEntry.importedAt,
            updatedAt: coreEntry.updatedAt,
            availability: availabilityChecker(coreEntry.path, coreEntry.sourcePath)
        )
    }
}

private enum FileAvailabilityResolver {
    static func availability(
        repoPath _: String,
        relativePath: String,
        sourcePath: String?,
        coreStatus: FileAvailabilityStatus
    ) -> FileAvailabilitySnapshot {
        if isICloudPlaceholder(relativePath) || sourcePath.map(isICloudPlaceholder) == true {
            return .iCloudPlaceholder
        }

        return FileAvailabilitySnapshot(coreStatus: coreStatus)
    }

    private static func isICloudPlaceholder(_ path: String) -> Bool {
        path.hasSuffix(".icloud") || path.contains(".icloud/")
    }
}

private extension FileAvailabilitySnapshot {
    init(coreStatus: FileAvailabilityStatus) {
        switch coreStatus {
        case .available:
            self = .available
        case .missing:
            self = .missing
        }
    }
}

private extension MissingFileStateSnapshot {
    init(coreState: MissingFileState) {
        fileID = coreState.fileId
        relativePath = coreState.relativePath
        lastKnownPath = coreState.lastKnownPath
        expectedHashSha256 = coreState.expectedHashSha256
        reason = MissingFileReasonSnapshot(coreReason: coreState.reason)
        canLocate = coreState.canLocate
    }
}

private extension MissingFileReasonSnapshot {
    init(coreReason: MissingFileReason) {
        switch coreReason {
        case .pathMissing:
            self = .pathMissing
        case .permissionDenied:
            self = .permissionDenied
        case .cloudPlaceholder:
            self = .cloudPlaceholder
        case .externalVolumeDisconnected:
            self = .externalVolumeDisconnected
        case .unknown:
            self = .unknown
        }
    }
}

private extension MissingFileRecoveryReportSnapshot {
    init(coreReport: MissingFileRecoveryReport) {
        fileID = coreReport.fileId
        status = MissingFileRecoveryStatusSnapshot(coreStatus: coreReport.status)
        previousPath = coreReport.previousPath
        currentPath = coreReport.currentPath
        hashMatched = coreReport.hashMatched
        fileDeleted = coreReport.fileDeleted
        message = coreReport.message
    }
}

private extension MissingFileRecoveryStatusSnapshot {
    init(coreStatus: MissingFileRecoveryStatus) {
        switch coreStatus {
        case .missing:
            self = .missing
        case .present:
            self = .present
        case .relinked:
            self = .relinked
        case .hashMismatch:
            self = .hashMismatch
        case .recordRemoved:
            self = .recordRemoved
        case .blocked:
            self = .blocked
        }
    }
}
