import SwiftUI

@MainActor
final class SyncConflictReviewRouteViewModel: ObservableObject {
    @Published private(set) var preview: SyncConflictResolutionPreviewReport?
    @Published private(set) var pendingConfirmation: SyncConflictReplaceConfirmation?
    @Published private(set) var result: SyncConflictResolveReport?
    @Published private(set) var error: SyncConflictEntryError?
    @Published private(set) var isPreviewing = false
    @Published private(set) var isApplying = false
    @Published private(set) var replaceAcknowledged = false

    let route: SyncConflictEntryReviewRoute
    private let bridge: any SyncConflictEntryCoreBridge

    init(route: SyncConflictEntryReviewRoute, bridge: any SyncConflictEntryCoreBridge) {
        self.route = route
        self.bridge = bridge
    }

    var canConfirmReplacePlan: Bool {
        guard let preview else { return false }
        return preview.resolution == .useIncoming
            && preview.replacePlan != nil
            && preview.normalizedPreviewToken != nil
            && preview.requiresReplaceConfirmation
            && preview.hasRecoverableOldVersion
            && (preview.canApply || preview.blocksOnlyForReplaceConfirmation)
            && !isPreviewing
            && !isApplying
    }

    var canApplyReplace: Bool {
        pendingConfirmation != nil && replaceAcknowledged && !isPreviewing && !isApplying
    }

    var replaceDisabledReason: String? {
        guard let preview else { return nil }
        if preview.replacePlan == nil {
            return "Could not build replace plan."
        }
        if preview.normalizedPreviewToken == nil {
            return "Replace preflight expired. Try again."
        }
        if !preview.hasRecoverableOldVersion {
            return "Replace is not available. Use Keep both."
        }
        if !preview.canApply && !preview.blocksOnlyForReplaceConfirmation {
            return preview.blockedReason ?? "Replace is not available."
        }
        if !preview.requiresReplaceConfirmation {
            return "Replace requires second confirmation."
        }
        if !replaceAcknowledged {
            return "Select confirmation to enable Replace."
        }
        return nil
    }

    func loadPreviewIfNeeded() async {
        guard preview == nil, !isPreviewing else { return }
        await refreshPreview()
    }

    func refreshPreview() async {
        isPreviewing = true
        error = nil
        result = nil
        pendingConfirmation = nil
        replaceAcknowledged = false
        do {
            preview = try await bridge.previewSyncConflictResolution(
                repoPath: route.repoPath,
                conflictID: route.conflictID,
                resolution: .useIncoming
            )
        } catch {
            self.error = SyncConflictEntryError.map(error)
        }
        isPreviewing = false
    }

    func setReplaceAcknowledged(_ value: Bool) {
        replaceAcknowledged = value
        updatePendingConfirmation()
    }

    func applyReplace() async {
        guard canApplyReplace, let confirmation = pendingConfirmation else { return }
        isApplying = true
        error = nil
        do {
            result = try await bridge.resolveSyncConflict(
                repoPath: route.repoPath,
                conflictID: confirmation.conflictID,
                request: SyncConflictResolutionRequest(
                    strategy: .useIncoming,
                    previewToken: confirmation.previewToken,
                    replaceConfirmed: true,
                    replaceConfirmationID: confirmation.confirmationID
                )
            )
            pendingConfirmation = nil
            replaceAcknowledged = false
        } catch {
            self.error = SyncConflictEntryError.map(error)
        }
        isApplying = false
    }

    private func updatePendingConfirmation() {
        guard replaceAcknowledged,
              canConfirmReplacePlan,
              let preview,
              let plan = preview.replacePlan,
              let token = preview.normalizedPreviewToken else {
            pendingConfirmation = nil
            return
        }
        pendingConfirmation = SyncConflictReplaceConfirmation(
            conflictID: preview.conflictID,
            previewToken: token,
            confirmationID: confirmationID(conflictID: preview.conflictID, previewToken: token),
            replacePlan: plan
        )
    }

    private func confirmationID(conflictID: String, previewToken: String) -> String {
        let safeToken = previewToken
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            .prefix(24)
        return "S4-X-09-C4-21-\(conflictID)-\(safeToken)"
    }
}

struct SyncConflictReviewRouteView: View {
    @StateObject private var model: SyncConflictReviewRouteViewModel

    init(
        route: SyncConflictEntryReviewRoute,
        bridge: any SyncConflictEntryCoreBridge = LiveMobileRepositoryCoreBridge()
    ) {
        _model = StateObject(wrappedValue: SyncConflictReviewRouteViewModel(route: route, bridge: bridge))
    }

    var body: some View {
        List {
            reviewHeader
            previewState
            if let preview = model.preview {
                replacePlanSection(preview)
                confirmationSection(preview)
            }
            if let result = model.result {
                resultSection(result)
            }
        }
        .mobileLibraryListStyle()
        .navigationTitle("Confirm Replace")
        .accessibilityIdentifier("S4-X-01-C4-15-ios-review-route")
        .task {
            await model.loadPreviewIfNeeded()
        }
    }
}

private extension SyncConflictReviewRouteView {
    var reviewHeader: some View {
        Section {
            Label("Review sync conflict", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(model.route.primaryPath)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Conflict ID: \(model.route.conflictID)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    var previewState: some View {
        Section("Replace preview") {
            if model.isPreviewing {
                ProgressView("Checking recovery options...")
            } else if let error = model.error {
                Label(error.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error.recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await model.refreshPreview() }
                }
            } else if model.preview == nil {
                Text("Replace is not available.")
                    .foregroundStyle(.secondary)
            } else {
                Label("Replace plan loaded from AreaMatrix Core.", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
        .accessibilityIdentifier("S4-X-09-C4-16-ios-preview")
    }

    func replacePlanSection(_ preview: SyncConflictResolutionPreviewReport) -> some View {
        Section("Replace plan") {
            if let plan = preview.replacePlan {
                planRow("Existing file", value: plan.oldPath)
                planRow("Incoming file", value: plan.newPath)
                planRow("Old hash", value: plan.oldHashPrefix)
                planRow("New hash", value: plan.newHashPrefix)
                planRow("Affected record", value: plan.affectedRecordText)
                planRow("Old version kept at", value: plan.backupTargetText)
                planRow("Database update", value: plan.databaseUpdate)
                planRow("Change log", value: plan.changeLogAction)
                planRow("Recovery note", value: plan.recoveryNote)
            } else {
                Text("Could not build replace plan.")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("S4-X-09-C4-21-ios-replace-plan")
    }

    func confirmationSection(_ preview: SyncConflictResolutionPreviewReport) -> some View {
        Section("Confirm Replace") {
            Toggle(isOn: Binding(
                get: { model.replaceAcknowledged },
                set: { model.setReplaceAcknowledged($0) }
            )) {
                Text("I understand this will replace the existing file.")
            }
            .disabled(!model.canConfirmReplacePlan)
            .accessibilityIdentifier("S4-X-09-C4-21-ios-confirmation")

            if let reason = model.replaceDisabledReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if preview.trashRequired && !preview.trashAvailable {
                Text("Trash is unavailable. Stage 4 does not allow irreversible Replace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                Task { await model.applyReplace() }
            } label: {
                if model.isApplying {
                    ProgressView()
                } else {
                    Text("Replace")
                }
            }
            .disabled(!model.canApplyReplace)
            .accessibilityIdentifier("S4-X-09-C4-21-ios-apply-replace")
        }
        .accessibilityIdentifier("S4-X-09-C4-21-ios-replace-confirm")
    }

    func resultSection(_ result: SyncConflictResolveReport) -> some View {
        Section("Result") {
            Label("Resolved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            planRow("Conflict ID", value: result.conflictID)
            planRow("Change log", value: result.changeLogAction)
            if let undoToken = result.undoToken {
                planRow("Undo token", value: undoToken)
            }
        }
        .accessibilityIdentifier("S4-X-09-C4-16-ios-resolve-result")
    }

    func planRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote)
                .textSelection(.enabled)
        }
    }
}
