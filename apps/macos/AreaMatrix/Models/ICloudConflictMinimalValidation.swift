import Combine
import Foundation

struct ICloudConflictVersionSnapshot: Equatable, Identifiable, Sendable {
    enum Role: String, Equatable, Sendable {
        case original
        case conflictedCopy
    }

    var role: Role
    var path: String?
    var modifiedAt: Int64?
    var sizeBytes: Int64?

    var id: Role { role }

    var displayName: String {
        guard let path, !path.isEmpty else { return "Unknown file" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var pathLabel: String {
        path ?? "Unknown path"
    }
}

enum ICloudConflictRepositoryValidationState: Equatable, Sendable {
    case notChecked
    case checking
    case ready(RepoPathValidationSnapshot, warnings: [String])
    case blocked(RepoPathValidationSnapshot, reasons: [String])
    case failed(ICloudConflictRepositoryValidationFailure)

    var allowsKeepBothApply: Bool {
        if case .ready = self { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

struct ICloudConflictRepositoryValidationFailure: Equatable, Sendable {
    var title: String
    var message: String
    var recovery: String

    init(error: Error) {
        guard let coreError = error as? CoreError else {
            title = "Repository could not be checked"
            message = error.localizedDescription
            recovery = "Retry the repository check or return to the conflict list."
            return
        }

        switch coreError {
        case .InvalidPath(let path):
            title = "Repository path is invalid"
            message = path
            recovery = "Choose the AreaMatrix repository root and retry."
        case .PermissionDenied(let path):
            title = "Repository needs permission"
            message = path
            recovery = "Grant folder access or choose the repository again."
        case .ICloudPlaceholder(let path):
            title = "iCloud item is not downloaded"
            message = path
            recovery = "Download the item in Finder, then retry."
        case .RepoNotInitialized(let path):
            title = "Repository is not initialized"
            message = path
            recovery = "Open an initialized AreaMatrix repository."
        case .Io(let message), .Db(let message), .Internal(let message):
            title = "Repository check failed"
            self.message = message
            recovery = "Retry the repository check before applying conflict resolution."
        case .Config(let reason), .Classify(let reason):
            title = "Repository check failed"
            message = reason
            recovery = "Review repository metadata and retry."
        case .Conflict(let path), .DuplicateFile(let path), .FileNotFound(let path):
            title = "Repository check failed"
            message = path
            recovery = "Return to the conflict list and refresh the repository state."
        }
    }
}

@MainActor
final class ICloudConflictMinimalModel: ObservableObject {
    @Published private(set) var repositoryValidationState: ICloudConflictRepositoryValidationState = .notChecked

    let repoPath: String
    let originalVersion: ICloudConflictVersionSnapshot
    let conflictedCopyVersion: ICloudConflictVersionSnapshot

    private let pathValidator: any CoreRepositoryPathValidating
    private var validationGeneration = 0

    init(
        repoPath: String,
        originalVersion: ICloudConflictVersionSnapshot,
        conflictedCopyVersion: ICloudConflictVersionSnapshot,
        pathValidator: any CoreRepositoryPathValidating = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.originalVersion = originalVersion
        self.conflictedCopyVersion = conflictedCopyVersion
        self.pathValidator = pathValidator
    }

    var canApplyKeepBoth: Bool {
        repositoryValidationState.allowsKeepBothApply
    }

    func validateRepositoryPath() async {
        validationGeneration += 1
        let currentGeneration = validationGeneration
        repositoryValidationState = .checking

        do {
            let validation = try await pathValidator.validateRepoPath(repoPath: repoPath)
            guard validationGeneration == currentGeneration else { return }
            repositoryValidationState = Self.state(for: validation)
        } catch {
            guard validationGeneration == currentGeneration else { return }
            repositoryValidationState = .failed(ICloudConflictRepositoryValidationFailure(error: error))
        }
    }

    private static func state(for validation: RepoPathValidationSnapshot) -> ICloudConflictRepositoryValidationState {
        let reasons = blockingReasons(for: validation)
        if !reasons.isEmpty {
            return .blocked(validation, reasons: reasons)
        }
        return .ready(validation, warnings: warnings(for: validation))
    }

    private static func blockingReasons(for validation: RepoPathValidationSnapshot) -> [String] {
        var reasons: [String] = []
        if !validation.exists || validation.issues.contains(.missingPath) {
            reasons.append("Repository folder is missing.")
        }
        if !validation.isDirectory || validation.issues.contains(.notDirectory) {
            reasons.append("Selected path is not a folder.")
        }
        if !validation.isReadable || validation.issues.contains(.notReadable) {
            reasons.append("Repository folder is not readable.")
        }
        if !validation.isWritable || validation.issues.contains(.notWritable) {
            reasons.append("Repository folder is not writable.")
        }
        if validation.isInsideAreaMatrix || validation.issues.contains(.insideAreaMatrix) {
            reasons.append("Use the repository root, not the .areamatrix metadata folder.")
        }
        if !validation.isInitialized {
            reasons.append("This folder is not an initialized AreaMatrix repository.")
        }
        if validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession) {
            reasons.append("Repository scan is unfinished; refresh after the scan completes.")
        }
        return reasons
    }

    private static func warnings(for validation: RepoPathValidationSnapshot) -> [String] {
        var warnings: [String] = []
        if validation.isICloudPath || validation.issues.contains(.iCloudPath) {
            warnings.append("Repository is in iCloud Drive; validation does not download placeholders.")
        }
        return warnings
    }
}
