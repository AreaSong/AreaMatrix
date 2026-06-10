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
    static let page = "S4-X-01-C4-15-sync-conflict-review"
    static let loading = "S4-X-01-C4-15-loading"
    static let empty = "S4-X-01-C4-15-empty"
    static let error = "S4-X-01-C4-15-error"
    static let retry = "S4-X-01-C4-15-retry"
    static let refresh = "S4-X-01-C4-15-refresh"
    static let back = "S4-X-01-C4-15-back"
    static let close = "S4-X-01-C4-15-close"
    static let summary = "S4-X-01-C4-15-summary"
    static let versions = "S4-X-01-C4-15-versions"
    static let resolution = "S4-X-01-C4-16-resolution"
    static let impact = "S4-X-01-C4-16-impact"
    static let apply = "S4-X-01-C4-16-apply"
    static let applyFailure = "S4-X-01-C4-16-apply-failure"
    static let applySuccess = "S4-X-01-C4-16-apply-success"
    static let replaceConfirmation = "S4-X-09-C4-21-replace-confirmation"
    static let replaceConfirm = "S4-X-09-C4-21-confirm-replace-plan"

    static func versionCard(fileID: String) -> String {
        "S4-X-01-C4-15-version-\(safeID(fileID))"
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
                summarySection(conflict)
                versionSection(conflict.affectedFiles)
                resolutionSection(conflict)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summarySection(_ conflict: SyncConflictSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(conflict.summaryDisplay)
                    .font(.headline)
                metadataGrid(rows: [
                    ("Conflict type", conflict.conflictType.displayName),
                    ("File", conflict.primaryPath),
                    ("Status", conflict.status.displayName),
                    ("Severity", conflict.severity.displayName),
                    ("Versions", "\(conflict.versionCount)"),
                    ("Source", conflict.sourceDisplay),
                    ("Detected", conflict.detectedDisplay),
                    ("Conflict ID", conflict.conflictID)
                ])
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.summary)
    }

    private func versionSection(_ files: [SyncConflictAffectedFileSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Versions")
                .font(.headline)
            ForEach(files) { file in
                versionCard(file)
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.versions)
    }

    private func versionCard(_ file: SyncConflictAffectedFileSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(file.role.displayName)
                    .font(.headline)
                metadataGrid(rows: [
                    ("Path", file.path),
                    ("Size", file.sizeDisplay),
                    ("Modified", file.modifiedDisplay),
                    ("Hash", file.hashDisplay),
                    ("Source platform", file.sourceDisplay),
                    ("File ID", file.fileID.map(String.init) ?? "Unknown")
                ])
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.versionCard(fileID: file.id))
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
            mappedFailure("Could not build \(strategy.title) impact.", mapping: mapping)
        }
    }

    private func previewSummary(_ preview: SyncConflictResolutionPreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            metadataGrid(rows: [
                ("Strategy", preview.resolution.title),
                ("Status after apply", preview.statusAfter.displayName),
                ("Canonical path", preview.canonicalPath ?? "Unchanged"),
                ("Change log", preview.changeLogAction),
                ("Affected records", listDisplay(preview.affectedFileIDs.map(String.init))),
                ("Kept paths", listDisplay(preview.keptPaths)),
                ("Retained paths", listDisplay(preview.retainedPaths)),
                ("Trash paths", listDisplay(preview.plannedTrashPaths))
            ])
            if preview.requiresReplaceConfirmation {
                Label("Use incoming version requires S4-X-09 replace confirmation.", systemImage: "lock.shield")
                    .foregroundStyle(.orange)
            }
            replaceConfirmationContent(preview)
            if let blockedReason = preview.blockedReasonDisplay {
                Label(blockedReason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            versionImpactList(preview.versionImpacts)
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

    private func versionImpactList(_ impacts: [SyncConflictVersionImpactSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SyncConflictReviewCopy.impactTitle)
                .font(.headline)
            ForEach(impacts) { impact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(impact.path)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    metadataGrid(rows: [
                        ("Role", impact.role.displayName),
                        ("File ID", impact.fileIDDisplay),
                        ("Keep", yesNo(impact.willKeep)),
                        ("Canonical", yesNo(impact.willBeCanonical)),
                        ("User visible", yesNo(impact.willRemainUserVisible)),
                        ("Move to Trash", yesNo(impact.willMoveToTrash)),
                        ("Recovery target", impact.recoveryDisplay),
                        ("Reason", impact.reasonDisplay)
                    ])
                }
                Divider()
            }
        }
    }

    @ViewBuilder
    private var applyResultContent: some View {
        switch model.applyState {
        case .idle, .applying:
            EmptyView()
        case let .succeeded(report):
            applySuccess(report)
        case let .failed(strategy, mapping):
            mappedFailure("Apply failed for \(strategy.title).", mapping: mapping)
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.applyFailure)
        }
    }

    private func applySuccess(_ report: SyncConflictResolveReportSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Resolution applied.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
            metadataGrid(rows: [
                ("Conflict ID", report.conflictID),
                ("Status", report.status.displayName),
                ("Change log", report.changeLogAction),
                ("Kept paths", listDisplay(report.keptPaths)),
                ("Retained paths", listDisplay(report.retainedPaths)),
                ("Trashed paths", listDisplay(report.trashedPaths)),
                ("Undo token", report.undoToken ?? "None")
            ])
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.applySuccess)
    }

    private func mappedFailure(_ title: String, mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Text(mapping.userMessage)
            Text(mapping.suggestedAction)
                .foregroundStyle(.secondary)
            if !mapping.rawContext.isEmpty {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
    }

    private func listDisplay(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func metadataGrid(rows: [(String, String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Text(row.1)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .font(.callout)
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
