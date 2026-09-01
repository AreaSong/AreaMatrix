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
        guard let path, !path.isEmpty else { return L10n.string("Unknown file") }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var pathLabel: String {
        path ?? L10n.string("Unknown path")
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

enum ICloudConflictPreviewState: Equatable {
    case notLoaded
    case loading
    case loaded(ICloudConflictPreviewSnapshot)
    case empty
    case failed(CoreErrorMappingSnapshot)

    var preview: ICloudConflictPreviewSnapshot? {
        guard case let .loaded(preview) = self else { return nil }
        return preview
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum ICloudConflictResolutionSubmissionResult: Equatable {
    case resolved(ICloudConflictResolutionResult)
    case failed(CoreErrorMappingSnapshot)
}

@MainActor
final class ICloudConflictMinimalModel: ObservableObject {
    @Published private(set) var repositoryValidationState: ICloudConflictRepositoryValidationState = .notChecked
    @Published private(set) var previewState: ICloudConflictPreviewState = .notLoaded

    let repoPath: String
    let conflictID: String?
    let originalVersion: ICloudConflictVersionSnapshot
    let conflictedCopyVersion: ICloudConflictVersionSnapshot

    private let pathValidator: any CoreRepositoryPathValidating
    private let conflictReviewer: (any CoreICloudConflictReviewing)?
    private let errorMapper: any CoreErrorMapping
    private var validationGeneration = 0
    private var previewGeneration = 0

    init(
        repoPath: String,
        conflictID: String? = nil,
        originalVersion: ICloudConflictVersionSnapshot,
        conflictedCopyVersion: ICloudConflictVersionSnapshot,
        pathValidator: any CoreRepositoryPathValidating,
        conflictReviewer: (any CoreICloudConflictReviewing)?,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.conflictID = conflictID
        self.originalVersion = originalVersion
        self.conflictedCopyVersion = conflictedCopyVersion
        self.pathValidator = pathValidator
        self.conflictReviewer = conflictReviewer
        self.errorMapper = errorMapper
    }

    var canApplyKeepBoth: Bool {
        guard repositoryValidationState.allowsKeepBothApply,
              let preview = effectivePreview else { return false }
        return preview.canKeepBoth && option(for: .keepBoth)?.enabled == true
    }

    var canResolveDestructive: Bool {
        guard repositoryValidationState.allowsKeepBothApply,
              let preview = effectivePreview else { return false }
        return preview.canResolveDestructive && preview.trashAvailable
    }

    var previewVersions: [ICloudConflictVersionMetadataSnapshot] {
        effectivePreview?.versions ?? fallbackPreviewVersions
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
            repositoryValidationState = await .failed(errorMapper.mapError(error))
        }
    }

    func loadPreviewIfNeeded() async {
        guard case .notLoaded = previewState else { return }
        await loadPreview()
    }

    func loadPreview() async {
        guard let reviewer = conflictReviewer else {
            previewState = .loaded(fallbackPreview)
            return
        }
        guard let conflictID, !conflictID.isEmpty else {
            previewState = .empty
            return
        }

        previewGeneration += 1
        let currentGeneration = previewGeneration
        previewState = .loading

        do {
            let preview = try await reviewer.previewICloudConflict(repoPath: repoPath, conflictID: conflictID)
            guard previewGeneration == currentGeneration else { return }
            previewState = preview.versions.isEmpty ? .empty : .loaded(preview)
        } catch {
            guard previewGeneration == currentGeneration else { return }
            previewState = await .failed(errorMapper.mapError(error))
        }
    }

    func option(for strategy: ICloudConflictResolutionStrategy) -> ICloudConflictResolutionOptionSnapshot? {
        effectivePreview?.resolutionOptions.first { $0.resolution == strategy } ??
            fallbackOption(for: strategy)
    }

    func canApply(
        strategy: ICloudConflictResolutionStrategy,
        isTrashAvailable: Bool,
        didConfirmSingleVersion: Bool
    ) -> Bool {
        guard repositoryValidationState.allowsKeepBothApply,
              let preview = effectivePreview,
              option(for: strategy)?.enabled == true else { return false }
        if !strategy.requiresSecondConfirmation {
            return preview.canKeepBoth
        }
        return preview.canResolveDestructive
            && preview.trashAvailable
            && isTrashAvailable
            && didConfirmSingleVersion
    }

    func resolveConflict(strategy: ICloudConflictResolutionStrategy) async
        -> ICloudConflictResolutionSubmissionResult {
        guard let reviewer = conflictReviewer,
              let conflictID,
              !conflictID.isEmpty else {
            let mapping = await errorMapper.mapError(
                AppSemanticError.conflict(rawContext: "missing iCloud conflict id")
            )
            return .failed(mapping)
        }

        do {
            guard let preview = previewState.preview,
                  !preview.previewToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppSemanticError.conflict(rawContext: "missing iCloud conflict preview token")
            }
            let result = try await reviewer.resolvePreviewedICloudConflict(ICloudConflictResolutionRequest(
                repoPath: repoPath,
                conflictID: conflictID,
                previewToken: preview.previewToken,
                fileID: -1,
                strategy: strategy,
                originalPath: originalVersion.path,
                conflictedCopyPath: conflictedCopyVersion.path
            ))
            try validateResolutionResult(result)
            return .resolved(result)
        } catch {
            let mapping = await errorMapper.mapError(error)
            return .failed(mapping)
        }
    }

    func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
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
            reasons.append(L10n.string("Repository folder is missing."))
        }
        if !validation.isDirectory || validation.issues.contains(.notDirectory) {
            reasons.append(L10n.string("Selected path is not a folder."))
        }
        if !validation.isReadable || validation.issues.contains(.notReadable) {
            reasons.append(L10n.string("Repository folder is not readable."))
        }
        if !validation.isWritable || validation.issues.contains(.notWritable) {
            reasons.append(L10n.string("Repository folder is not writable."))
        }
        if validation.isInsideAreaMatrix || validation.issues.contains(.insideAreaMatrix) {
            reasons.append(L10n.string("Use the repository root, not the .areamatrix metadata folder."))
        }
        if !validation.isInitialized {
            reasons.append(L10n.string("This folder is not an initialized AreaMatrix repository."))
        }
        if validation.hasUnfinishedScanSession || validation.issues.contains(.unfinishedScanSession) {
            reasons.append(L10n.string("Repository scan is unfinished; refresh after the scan completes."))
        }
        return reasons
    }

    private static func warnings(for validation: RepoPathValidationSnapshot) -> [String] {
        var warnings: [String] = []
        if validation.isICloudPath || validation.issues.contains(.iCloudPath) {
            warnings.append(L10n.string("Repository is in iCloud Drive; validation does not download placeholders."))
        }
        return warnings
    }

    private var fallbackPreviewVersions: [ICloudConflictVersionMetadataSnapshot] {
        [
            ICloudConflictVersionMetadataSnapshot(version: originalVersion),
            ICloudConflictVersionMetadataSnapshot(version: conflictedCopyVersion)
        ]
    }

    private var fallbackPreview: ICloudConflictPreviewSnapshot {
        ICloudConflictPreviewSnapshot(
            conflictID: conflictID ?? "",
            versions: fallbackPreviewVersions,
            defaultResolution: .keepBoth,
            resolutionOptions: [
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepBoth,
                    destructive: false,
                    requiresTrash: false,
                    enabled: true,
                    disabledReason: nil
                ),
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepOriginalOnly,
                    destructive: true,
                    requiresTrash: true,
                    enabled: false,
                    disabledReason: L10n.string("Core preview is unavailable for this route.")
                ),
                ICloudConflictResolutionOptionSnapshot(
                    resolution: .keepConflictedCopyOnly,
                    destructive: true,
                    requiresTrash: true,
                    enabled: false,
                    disabledReason: L10n.string("Core preview is unavailable for this route.")
                )
            ],
            metadataComplete: false,
            trashAvailable: false,
            canKeepBoth: true,
            canResolveDestructive: false,
            blockedReason: L10n.string("Core preview is unavailable for this route.")
        )
    }

    private var effectivePreview: ICloudConflictPreviewSnapshot? {
        if let preview = previewState.preview { return preview }
        guard conflictReviewer == nil else { return nil }
        return fallbackPreview
    }

    private func fallbackOption(
        for strategy: ICloudConflictResolutionStrategy
    ) -> ICloudConflictResolutionOptionSnapshot? {
        guard case .empty = previewState else { return nil }
        return ICloudConflictResolutionOptionSnapshot(
            resolution: strategy,
            destructive: strategy.requiresSecondConfirmation,
            requiresTrash: strategy.requiresSecondConfirmation,
            enabled: false,
            disabledReason: L10n.string("Conflict no longer exists")
        )
    }

    private func validateResolutionResult(_ result: ICloudConflictResolutionResult) throws {
        guard result.didClearConflictState else {
            throw AppSemanticError.internalFailure(rawContext: "iCloud conflict did not clear conflict state")
        }
        guard result.didWriteChangeLog else {
            throw AppSemanticError.internalFailure(rawContext: "iCloud conflict did not write change_log")
        }
    }
}

private extension ICloudConflictVersionMetadataSnapshot {
    init(version: ICloudConflictVersionSnapshot) {
        versionID = version.role.rawValue
        role = ICloudConflictVersionRoleSnapshot(versionRole: version.role)
        path = version.path ?? ""
        modifiedAt = version.modifiedAt
        sizeBytes = version.sizeBytes
        hashSha256 = nil
        previewSummary = nil
        previewStatus = .metadataOnly
    }
}

private extension ICloudConflictVersionRoleSnapshot {
    init(versionRole: ICloudConflictVersionSnapshot.Role) {
        switch versionRole {
        case .original:
            self = .original
        case .conflictedCopy:
            self = .conflictedCopy
        }
    }
}
