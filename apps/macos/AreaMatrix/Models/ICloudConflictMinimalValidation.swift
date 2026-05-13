import Combine
import Foundation

struct ICloudConflictVersionSnapshot: Equatable, Identifiable {
    enum Role: String, Equatable {
        case original
        case conflictedCopy
    }

    var role: Role
    var path: String?
    var modifiedAt: Int64?
    var sizeBytes: Int64?

    var id: Role {
        role
    }

    var displayName: String {
        guard let path, !path.isEmpty else { return "Unknown file" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var pathLabel: String {
        path ?? "Unknown path"
    }
}

enum ICloudConflictRepositoryValidationState: Equatable {
    case notChecked
    case checking
    case ready(RepoPathValidationSnapshot, warnings: [String])
    case blocked(RepoPathValidationSnapshot, reasons: [String])
    case failed(CoreErrorMappingSnapshot)

    var allowsKeepBothApply: Bool {
        if case .ready = self { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

@MainActor
final class ICloudConflictMinimalModel: ObservableObject {
    @Published private(set) var repositoryValidationState: ICloudConflictRepositoryValidationState = .notChecked

    let repoPath: String
    let originalVersion: ICloudConflictVersionSnapshot
    let conflictedCopyVersion: ICloudConflictVersionSnapshot

    private let pathValidator: any CoreRepositoryPathValidating
    private let errorMapper: any CoreErrorMapping
    private var validationGeneration = 0

    init(
        repoPath: String,
        originalVersion: ICloudConflictVersionSnapshot,
        conflictedCopyVersion: ICloudConflictVersionSnapshot,
        pathValidator: any CoreRepositoryPathValidating = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.originalVersion = originalVersion
        self.conflictedCopyVersion = conflictedCopyVersion
        self.pathValidator = pathValidator
        self.errorMapper = errorMapper
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
            repositoryValidationState = await .failed(mapValidationError(error))
        }
    }

    private func mapValidationError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
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
