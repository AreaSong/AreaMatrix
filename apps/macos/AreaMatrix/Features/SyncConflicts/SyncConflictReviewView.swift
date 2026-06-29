import SwiftUI

enum SyncConflictReviewCopy {
    static let title = "Review sync conflict"
    static let subtitle = "Compare detected versions before choosing a resolution."
    static let loadingTitle = "Loading conflict details..."
    static let emptyTitle = "Conflict no longer exists."
    static let errorTitle = "Unable to load sync conflict"
    static let backAction = "Back to Needs Review"
    static let refreshAction = "Refresh"
    static let closeAction = "Close"
    static let applyAction = "Apply resolution"
    static let applyingAction = "Applying resolution..."
    static let impactTitle = "Impact summary"
    static let resolutionTitle = "Resolution"
    static let replaceConfirmAction = "Confirm replace plan"
}

enum SyncConflictReviewAccessibilityID {
    static let page = "sync-conflict-review-sync-conflict-detect-sync-conflict-review"
    static let loading = "sync-conflict-review-sync-conflict-detect-loading"
    static let empty = "sync-conflict-review-sync-conflict-detect-empty"
    static let error = "sync-conflict-review-sync-conflict-detect-error"
    static let retry = "sync-conflict-review-sync-conflict-detect-retry"
    static let refresh = "sync-conflict-review-sync-conflict-detect-refresh"
    static let back = "sync-conflict-review-sync-conflict-detect-back"
    static let close = "sync-conflict-review-sync-conflict-detect-close"
    static let summary = "sync-conflict-review-sync-conflict-detect-summary"
    static let versions = "sync-conflict-review-sync-conflict-detect-versions"
    static let resolution = "sync-conflict-review-sync-conflict-resolve-resolution"
    static let impact = "sync-conflict-review-sync-conflict-resolve-impact"
    static let apply = "sync-conflict-review-sync-conflict-resolve-apply"
    static let applyFailure = "sync-conflict-review-sync-conflict-resolve-apply-failure"
    static let applySuccess = "sync-conflict-review-sync-conflict-resolve-apply-success"
    static let replaceConfirmation = "replace-resolution-replace-confirmation-replace-confirmation"
    static let replaceConfirm = "replace-resolution-replace-confirmation-confirm-replace-plan"

    static func versionCard(fileID: String) -> String {
        "sync-conflict-review-sync-conflict-detect-version-\(safeID(fileID))"
    }

    private static func safeID(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? String(character)
                : "-"
        }.joined()
    }
}

struct SyncConflictReviewView: View {
    @StateObject private var model: SyncConflictReviewModel
    let onBackToNeedsReview: () -> Void
    let onClose: () -> Void
    let onResolved: @MainActor (SyncConflictResolveReportSnapshot) async -> Void

    init(
        model: SyncConflictReviewModel,
        onBackToNeedsReview: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onResolved: @escaping @MainActor (SyncConflictResolveReportSnapshot) async -> Void = { _ in }
    ) {
        _model = StateObject(wrappedValue: model)
        self.onBackToNeedsReview = onBackToNeedsReview
        self.onClose = onClose
        self.onResolved = onResolved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            if case .notLoaded = model.state {
                await model.load()
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.page)
    }
}

private extension SyncConflictReviewView {
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(SyncConflictReviewCopy.title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(SyncConflictReviewCopy.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(SyncConflictReviewCopy.loadingTitle)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .notLoaded, .loading:
            loadingContent
        case let .loaded(conflict):
            conflictContent(conflict)
        case .empty:
            emptyContent
        case let .failed(mapping):
            errorContent(mapping)
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(SyncConflictReviewCopy.loadingTitle)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.loading)
    }

    private var emptyContent: some View {
        ContentUnavailableView {
            Label(SyncConflictReviewCopy.emptyTitle, systemImage: "checkmark.circle")
        } description: {
            Text("Refresh the conflict entry list and choose another item.")
        } actions: {
            Button(SyncConflictReviewCopy.backAction, action: onBackToNeedsReview)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.back)
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.empty)
    }

    private func errorContent(_ mapping: CoreErrorMappingSnapshot) -> some View {
        ContentUnavailableView {
            Label(SyncConflictReviewCopy.errorTitle, systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 4) {
                Text(mapping.userMessage)
                Text(mapping.suggestedAction)
                Text("Severity: \(mapping.severity.rawValue); Recoverability: \(mapping.recoverability.rawValue)")
                if !mapping.rawContext.isEmpty {
                    Text(mapping.rawContext)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } actions: {
            Button("Retry") {
                Task { await model.refresh() }
            }
            .accessibilityIdentifier(SyncConflictReviewAccessibilityID.retry)
            Button(SyncConflictReviewCopy.backAction, action: onBackToNeedsReview)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.back)
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.error)
    }

    private func conflictContent(_ conflict: SyncConflictSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SyncConflictReviewSummarySection(conflict: conflict)
                SyncConflictReviewVersionsSection(files: conflict.affectedFiles)
                resolutionSection(conflict)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func resolutionSection(_: SyncConflictSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Picker(SyncConflictReviewCopy.resolutionTitle, selection: resolutionSelection) {
                    ForEach(SyncConflictResolutionStrategySnapshot.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .pickerStyle(.segmented)
                Text(model.selectedResolution.impactSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                previewContent
                applyResultContent
            }
        } label: {
            Label(SyncConflictReviewCopy.resolutionTitle, systemImage: "checkmark.seal")
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.resolution)
    }

    private var resolutionSelection: Binding<SyncConflictResolutionStrategySnapshot> {
        Binding(
            get: { model.selectedResolution },
            set: { resolution in
                Task { await model.selectResolution(resolution) }
            }
        )
    }

    @ViewBuilder
    private var previewContent: some View {
        switch model.previewState {
        case .idle:
            Text("Resolution impact is required before applying.")
                .foregroundStyle(.secondary)
        case let .loading(strategy):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Building impact for \(strategy.title)...")
            }
            .foregroundStyle(.secondary)
        case let .loaded(preview):
            previewSummary(preview)
        case let .failed(strategy, mapping):
            SyncConflictReviewMappedFailure(title: "Could not build \(strategy.title) impact.", mapping: mapping)
        }
    }

    private func previewSummary(_ preview: SyncConflictResolutionPreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SyncConflictReviewMetadataGrid(rows: [
                ("Strategy", preview.resolution.title),
                ("Status after apply", preview.statusAfter.displayName),
                ("Canonical path", preview.canonicalPath ?? "Unchanged"),
                ("Change log", preview.changeLogAction),
                ("Affected records", SyncConflictReviewDisplayValue.list(preview.affectedFileIDs.map(String.init))),
                ("Kept paths", SyncConflictReviewDisplayValue.list(preview.keptPaths)),
                ("Retained paths", SyncConflictReviewDisplayValue.list(preview.retainedPaths)),
                ("Trash paths", SyncConflictReviewDisplayValue.list(preview.plannedTrashPaths))
            ])
            if preview.requiresReplaceConfirmation {
                Label(
                    "Use incoming version requires replace-resolution replace confirmation.",
                    systemImage: "lock.shield"
                )
                .foregroundStyle(.orange)
            }
            replaceConfirmationContent(preview)
            if let blockedReason = preview.blockedReasonDisplay {
                Label(blockedReason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            SyncConflictReviewVersionImpactList(impacts: preview.versionImpacts)
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.impact)
    }

    @ViewBuilder
    private func replaceConfirmationContent(_ preview: SyncConflictResolutionPreviewSnapshot) -> some View {
        if preview.requiresReplaceConfirmation || model.selectedResolution == .useIncoming {
            SyncConflictReplaceConfirmationPanel(
                preview: preview,
                confirmation: model.replaceConfirmation,
                disabledReason: model.replaceConfirmationDisabledReason,
                onConfirm: model.confirmReplacePlan
            )
            .id(preview.normalizedPreviewToken ?? preview.conflictID)
        }
    }

    @ViewBuilder
    private var applyResultContent: some View {
        switch model.applyState {
        case .idle, .applying:
            EmptyView()
        case let .succeeded(report):
            SyncConflictReviewApplySuccess(report: report)
        case let .failed(strategy, mapping):
            SyncConflictReviewMappedFailure(title: "Apply failed for \(strategy.title).", mapping: mapping)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.applyFailure)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(SyncConflictReviewCopy.backAction, action: onBackToNeedsReview)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.back)
            Spacer()
            Button(SyncConflictReviewCopy.refreshAction) {
                Task { await model.refresh() }
            }
            .accessibilityIdentifier(SyncConflictReviewAccessibilityID.refresh)
            Button(applyButtonTitle) {
                Task {
                    await applySelectedResolution()
                }
            }
            .disabled(!model.canApplyResolution)
            .help(model.applyDisabledReason ?? "Apply the selected Core sync conflict resolution.")
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier(SyncConflictReviewAccessibilityID.apply)
            Button(SyncConflictReviewCopy.closeAction, action: onClose)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.close)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var applyButtonTitle: String {
        model.applyState.isApplying ? SyncConflictReviewCopy.applyingAction : SyncConflictReviewCopy.applyAction
    }
}

extension SyncConflictReviewView {
    @MainActor
    func applySelectedResolution() async {
        if let report = await model.applyResolution() {
            await onResolved(report)
        }
    }
}
