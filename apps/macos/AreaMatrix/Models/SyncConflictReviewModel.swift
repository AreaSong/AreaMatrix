import Combine
import Foundation

enum SyncConflictReviewState: Equatable {
    case notLoaded
    case loading
    case loaded(SyncConflictSnapshot)
    case empty
    case failed(CoreErrorMappingSnapshot)

    var conflict: SyncConflictSnapshot? {
        guard case let .loaded(conflict) = self else { return nil }
        return conflict
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum SyncConflictResolutionPreviewState: Equatable {
    case idle
    case loading(SyncConflictResolutionStrategySnapshot)
    case loaded(SyncConflictResolutionPreviewSnapshot)
    case failed(SyncConflictResolutionStrategySnapshot, CoreErrorMappingSnapshot)

    var preview: SyncConflictResolutionPreviewSnapshot? {
        guard case let .loaded(preview) = self else { return nil }
        return preview
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

enum SyncConflictResolutionApplyState: Equatable {
    case idle
    case applying(SyncConflictResolutionStrategySnapshot)
    case succeeded(SyncConflictResolveReportSnapshot)
    case failed(SyncConflictResolutionStrategySnapshot, CoreErrorMappingSnapshot)

    var isApplying: Bool {
        if case .applying = self { return true }
        return false
    }
}

struct SyncConflictReplaceConfirmationSnapshot: Equatable {
    var conflictID: String
    var previewToken: String
    var confirmationID: String
    var replacePlan: SyncConflictReplacePlanSnapshot
}

@MainActor
final class SyncConflictReviewModel: ObservableObject {
    @Published private(set) var state: SyncConflictReviewState = .notLoaded
    @Published private(set) var selectedResolution: SyncConflictResolutionStrategySnapshot = .keepBoth
    @Published private(set) var previewState: SyncConflictResolutionPreviewState = .idle
    @Published private(set) var applyState: SyncConflictResolutionApplyState = .idle
    @Published private(set) var replaceConfirmation: SyncConflictReplaceConfirmationSnapshot?

    let repoPath: String
    let conflictID: String?
    let primaryPath: String?
    private let conflictDetector: any CoreSyncConflictDetecting
    private let conflictResolver: any CoreSyncConflictResolving
    private let errorMapper: any CoreErrorMapping
    private var loadGeneration = 0
    private var previewGeneration = 0

    init(
        repoPath: String,
        conflictID: String? = nil,
        primaryPath: String? = nil,
        conflictDetector: any CoreSyncConflictDetecting = CoreBridge(),
        conflictResolver: any CoreSyncConflictResolving = CoreBridge(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.conflictID = conflictID
        self.primaryPath = primaryPath
        self.conflictDetector = conflictDetector
        self.conflictResolver = conflictResolver
        self.errorMapper = errorMapper
    }

    var conflict: SyncConflictSnapshot? {
        state.conflict
    }

    var isLoading: Bool {
        state.isLoading
    }

    var canApplyResolution: Bool {
        applyDisabledReason == nil
    }

    var canConfirmReplacePlan: Bool {
        replaceConfirmationDisabledReason == nil
    }

    var applyDisabledReason: String? {
        guard let conflict else { return "Conflict details are not loaded." }
        guard case let .loaded(preview) = previewState else {
            return previewState.isLoading ? "Resolution impact is still loading." : "Resolution impact is required."
        }
        if case .succeeded = applyState {
            return "Resolution has already been applied."
        }
        if applyState.isApplying {
            return "Resolution is already applying."
        }
        if preview.conflictID != conflict.conflictID || preview.resolution != selectedResolution {
            return "Resolution impact does not match the selected conflict."
        }
        if requiresReplaceConfirmation(preview), !isReplaceConfirmed(for: preview) {
            return replaceConfirmationDisabledReason
                ?? "Confirm the S4-X-09 replace plan before applying Use incoming version."
        }
        if !preview.canApply, !canApplyConfirmedReplace(preview) {
            return preview.blockedReasonDisplay ?? "Core reported this resolution cannot be applied."
        }
        if preview.normalizedPreviewToken == nil {
            return "Core did not return a resolution preview token."
        }
        return nil
    }

    var replaceConfirmationDisabledReason: String? {
        guard let conflict else { return "Conflict details are not loaded." }
        guard case let .loaded(preview) = previewState else {
            return previewState.isLoading ? "Resolution impact is still loading." : "Resolution impact is required."
        }
        guard selectedResolution == .useIncoming || preview.requiresReplaceConfirmation else {
            return "Replace confirmation is only required for Use incoming version."
        }
        if preview.conflictID != conflict.conflictID || preview.resolution != selectedResolution {
            return "Resolution impact does not match the selected conflict."
        }
        guard preview.replacePlan != nil else {
            return "Core did not return a replace plan."
        }
        guard preview.normalizedPreviewToken != nil else {
            return "Core did not return a resolution preview token."
        }
        if preview.trashRequired, !preview.trashAvailable {
            return preview.blockedReasonDisplay ?? "Replace requires Trash or a Core safety backup."
        }
        if !preview.canApply, !preview.blocksOnlyForReplaceConfirmation {
            return preview.blockedReasonDisplay ?? "Core reported this replace plan cannot be applied."
        }
        return nil
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        state = .loading
        previewState = .idle
        applyState = .idle
        replaceConfirmation = nil

        do {
            let conflicts = try await conflictDetector.detectSyncConflicts(repoPath: repoPath)
            guard generation == loadGeneration else { return }
            guard let conflict = selectedConflict(from: conflicts) else {
                state = .empty
                return
            }
            selectedResolution = .keepBoth
            state = .loaded(conflict)
            await previewResolution(.keepBoth, conflict: conflict)
        } catch {
            guard generation == loadGeneration else { return }
            state = await .failed(mapError(error))
        }
    }

    func refresh() async {
        await load()
    }

    func selectResolution(_ resolution: SyncConflictResolutionStrategySnapshot) async {
        selectedResolution = resolution
        applyState = .idle
        replaceConfirmation = nil
        guard let conflict else {
            previewState = .idle
            return
        }
        await previewResolution(resolution, conflict: conflict)
    }

    func confirmReplacePlan() {
        guard replaceConfirmationDisabledReason == nil,
              let conflict,
              let preview = previewState.preview,
              let previewToken = preview.normalizedPreviewToken,
              let replacePlan = preview.replacePlan else { return }

        replaceConfirmation = SyncConflictReplaceConfirmationSnapshot(
            conflictID: conflict.conflictID,
            previewToken: previewToken,
            confirmationID: confirmationID(conflictID: conflict.conflictID, previewToken: previewToken),
            replacePlan: replacePlan
        )
    }

    @discardableResult
    func applyResolution() async -> SyncConflictResolveReportSnapshot? {
        guard canApplyResolution,
              let conflict,
              let preview = previewState.preview,
              let previewToken = preview.normalizedPreviewToken else { return nil }
        let confirmation = isReplaceConfirmed(for: preview) ? replaceConfirmation : nil

        applyState = .applying(selectedResolution)

        do {
            let report = try await conflictResolver.resolveSyncConflict(
                repoPath: repoPath,
                conflictID: conflict.conflictID,
                request: SyncConflictResolutionRequestSnapshot(
                    strategy: selectedResolution,
                    previewToken: previewToken,
                    replaceConfirmed: confirmation != nil,
                    replaceConfirmationID: confirmation?.confirmationID
                )
            )
            applyState = .succeeded(report)
            return report
        } catch {
            applyState = await .failed(selectedResolution, mapError(error))
            return nil
        }
    }

    private func previewResolution(
        _ resolution: SyncConflictResolutionStrategySnapshot,
        conflict: SyncConflictSnapshot
    ) async {
        previewGeneration += 1
        let generation = previewGeneration
        previewState = .loading(resolution)

        do {
            let preview = try await conflictResolver.previewSyncConflictResolution(
                repoPath: repoPath,
                conflictID: conflict.conflictID,
                resolution: resolution
            )
            guard generation == previewGeneration else { return }
            previewState = .loaded(preview)
        } catch {
            guard generation == previewGeneration else { return }
            replaceConfirmation = nil
            previewState = await .failed(resolution, mapError(error))
        }
    }

    private func selectedConflict(from conflicts: [SyncConflictSnapshot]) -> SyncConflictSnapshot? {
        let reviewableConflicts = conflicts.filter { $0.status == .needsReview }
        guard let conflictID else {
            guard let primaryPath = normalizedPrimaryPath else {
                return reviewableConflicts.first
            }
            return reviewableConflicts.first { $0.matches(path: primaryPath) }
        }
        return reviewableConflicts.first { $0.conflictID == conflictID }
    }

    private var normalizedPrimaryPath: String? {
        let trimmed = primaryPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func requiresReplaceConfirmation(_ preview: SyncConflictResolutionPreviewSnapshot) -> Bool {
        selectedResolution == .useIncoming || preview.requiresReplaceConfirmation
    }

    private func isReplaceConfirmed(for preview: SyncConflictResolutionPreviewSnapshot) -> Bool {
        guard let confirmation = replaceConfirmation,
              let previewToken = preview.normalizedPreviewToken else { return false }
        return confirmation.conflictID == preview.conflictID && confirmation.previewToken == previewToken
    }

    private func canApplyConfirmedReplace(_ preview: SyncConflictResolutionPreviewSnapshot) -> Bool {
        requiresReplaceConfirmation(preview)
            && isReplaceConfirmed(for: preview)
            && preview.blocksOnlyForReplaceConfirmation
    }

    private func confirmationID(conflictID: String, previewToken: String) -> String {
        let rawID = "\(conflictID)-\(previewToken)"
        let safeID = rawID.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? String(character)
                : "-"
        }.joined()
        return "S4-X-01-C4-21-\(safeID)"
    }
}

struct SyncConflictReviewRoute: Equatable, Identifiable {
    var repoPath: String
    var conflictID: String?
    var primaryPath: String?

    var id: String {
        [repoPath, conflictID ?? "", primaryPath ?? ""].joined(separator: "|")
    }

    static func fileDetail(repoPath: String, file: FileEntrySnapshot) -> SyncConflictReviewRoute {
        SyncConflictReviewRoute(repoPath: repoPath, conflictID: nil, primaryPath: file.path)
    }
}

private extension SyncConflictSnapshot {
    func matches(path: String) -> Bool {
        primaryPath == path || affectedFiles.contains { $0.path == path }
    }
}
