import Foundation

enum ICloudConflictResolutionStrategy: String, CaseIterable, Equatable, Identifiable {
    case keepBoth
    case keepOriginalOnly
    case keepConflictedCopyOnly

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .keepBoth:
            "保留两份（推荐）"
        case .keepOriginalOnly:
            "仅保留第一份（把另一份移到回收站）"
        case .keepConflictedCopyOnly:
            "仅保留第二份（把另一份移到回收站）"
        }
    }

    var actionTitle: String {
        switch self {
        case .keepBoth:
            "Apply"
        case .keepOriginalOnly, .keepConflictedCopyOnly:
            "Move other version to Trash and Apply"
        }
    }

    var runningTitle: String {
        switch self {
        case .keepBoth:
            "Applying..."
        case .keepOriginalOnly, .keepConflictedCopyOnly:
            "Moving to Trash..."
        }
    }

    var requiresSecondConfirmation: Bool {
        self != .keepBoth
    }

    var successMessage: String {
        switch self {
        case .keepBoth:
            "Both iCloud conflict versions kept. Conflict state and change log were refreshed."
        case .keepOriginalOnly:
            "Original version kept. The other version was handled through Core resolution."
        case .keepConflictedCopyOnly:
            "Conflicted copy kept. The other version was handled through Core resolution."
        }
    }
}

enum ICloudConflictResolutionState: Equatable {
    case idle
    case applying(fileID: Int64, strategy: ICloudConflictResolutionStrategy)
    case failed(fileID: Int64, strategy: ICloudConflictResolutionStrategy, CoreErrorMappingSnapshot)

    var isApplying: Bool {
        if case .applying = self { return true }
        return false
    }

    func isApplying(fileID: Int64) -> Bool {
        guard case let .applying(applyingFileID, _) = self else { return false }
        return applyingFileID == fileID
    }

    func failedStrategy(fileID: Int64) -> ICloudConflictResolutionStrategy? {
        guard case let .failed(failedFileID, strategy, _) = self,
              failedFileID == fileID else { return nil }
        return strategy
    }

    func failure(fileID: Int64) -> CoreErrorMappingSnapshot? {
        guard case let .failed(failedFileID, _, mapping) = self,
              failedFileID == fileID else { return nil }
        return mapping
    }

    func primaryTitle(
        fileID: Int64,
        selectedStrategy: ICloudConflictResolutionStrategy
    ) -> String {
        if isApplying(fileID: fileID) { return selectedStrategy.runningTitle }
        if failure(fileID: fileID) != nil { return "Retry" }
        return selectedStrategy.actionTitle
    }
}

struct ICloudConflictResolutionBlocker: Equatable {
    var title: String
    var message: String
    var suggestedAction: String
    var rawContext: String

    var coreError: CoreError {
        CoreError.Internal(message: rawContext)
    }

    static let missingCoreResolutionEndpoint = ICloudConflictResolutionBlocker(
        title: "Core resolution unavailable",
        message: """
        S1-25 can validate the repository and map errors, but the Core resolution endpoint that clears conflict state \
        and writes change_log is not available yet.
        """,
        suggestedAction: """
        Keep the conflict unresolved and return after the iCloud conflict resolution capability is implemented.
        """,
        rawContext: "Missing Core API: resolve_icloud_conflict or mark_icloud_conflict_resolved"
    )
}

enum ICloudConflictResolutionCapability: Equatable {
    case supported
    case blocked(ICloudConflictResolutionBlocker)

    var canResolve: Bool {
        if case .supported = self { return true }
        return false
    }

    var blocker: ICloudConflictResolutionBlocker? {
        guard case let .blocked(blocker) = self else { return nil }
        return blocker
    }
}

struct ICloudConflictResolutionRequest: Equatable {
    var repoPath: String
    var conflictID: String
    var fileID: Int64
    var strategy: ICloudConflictResolutionStrategy
    var originalPath: String?
    var conflictedCopyPath: String?
}

struct ICloudConflictResolutionResult: Equatable {
    var focusFileID: Int64?
    var conflictID: String? = nil
    var report: ICloudConflictResolveReportSnapshot? = nil
    var status: ICloudConflictStatusSnapshot? = nil
    var keptPaths: [String] = []
    var trashedPaths: [String] = []
    var undoToken: String? = nil
    var changeLogAction: String? = nil
    var didClearConflictState: Bool
    var didWriteChangeLog: Bool
}

extension ICloudConflictResolutionResult {
    init(report: ICloudConflictResolveReportSnapshot) {
        focusFileID = nil
        conflictID = report.conflictID
        self.report = report
        status = report.status
        keptPaths = report.keptPaths
        trashedPaths = report.trashedPaths
        undoToken = report.undoToken
        changeLogAction = report.changeLogAction
        didClearConflictState = report.status == .resolved
        didWriteChangeLog = !report.changeLogAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

protocol ICloudConflictResolving: Sendable {
    var iCloudConflictResolutionCapability: ICloudConflictResolutionCapability { get }

    func resolveICloudConflict(_ request: ICloudConflictResolutionRequest) async throws
        -> ICloudConflictResolutionResult
}
