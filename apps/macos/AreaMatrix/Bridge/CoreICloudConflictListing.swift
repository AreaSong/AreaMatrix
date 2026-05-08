import Foundation

protocol CoreICloudConflictListing: Sendable {
    func listICloudConflicts(repoPath: String) async throws -> [ICloudConflictPairSnapshot]
}

enum ICloudConflictStatusSnapshot: String, Equatable, Sendable {
    case needsReview = "NeedsReview"
    case resolved = "Resolved"

    var displayName: String {
        switch self {
        case .needsReview:
            return "Needs review"
        case .resolved:
            return "Resolved"
        }
    }
}

struct ICloudConflictPairSnapshot: Equatable, Identifiable, Sendable {
    var conflictID: String
    var originalPath: String?
    var conflictedCopyPath: String
    var originalModifiedAt: Int64?
    var conflictedModifiedAt: Int64
    var status: ICloudConflictStatusSnapshot
    var uncertaintyReason: String?

    var id: String { conflictID }

    var fileDisplayName: String {
        let path = originalPath ?? conflictedCopyPath
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? "Unknown file" : name
    }

    var originalVersionDisplay: String {
        originalPath ?? "Unknown original version"
    }

    var conflictedCopyDisplay: String {
        conflictedCopyPath
    }

    var modifiedDisplay: String {
        Date(timeIntervalSince1970: TimeInterval(conflictedModifiedAt))
            .formatted(date: .abbreviated, time: .shortened)
    }

    var statusDisplay: String {
        guard status == .needsReview, let uncertaintyReason, !uncertaintyReason.isEmpty else {
            return status.displayName
        }
        return "\(status.displayName): \(uncertaintyReason)"
    }
}

extension CoreBridge: CoreICloudConflictListing {
    func listICloudConflicts(repoPath: String) async throws -> [ICloudConflictPairSnapshot] {
        try await Task.detached(priority: .userInitiated) {
            try listCoreICloudConflicts(repoPath: repoPath).map(ICloudConflictPairSnapshot.init)
        }.value
    }
}

extension ICloudConflictPairSnapshot {
    init(corePair: ICloudConflictPair) {
        conflictID = corePair.conflictId
        originalPath = corePair.originalPath
        conflictedCopyPath = corePair.conflictedCopyPath
        originalModifiedAt = corePair.originalModifiedAt
        conflictedModifiedAt = corePair.conflictedModifiedAt
        status = ICloudConflictStatusSnapshot(coreStatus: corePair.status)
        uncertaintyReason = corePair.uncertaintyReason
    }
}

private extension ICloudConflictStatusSnapshot {
    init(coreStatus: ICloudConflictStatus) {
        switch coreStatus {
        case .needsReview:
            self = .needsReview
        case .resolved:
            self = .resolved
        }
    }
}

private func listCoreICloudConflicts(repoPath: String) throws -> [ICloudConflictPair] {
    try listIcloudConflicts(repoPath: repoPath)
}
