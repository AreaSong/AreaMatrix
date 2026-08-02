import SwiftUI

extension MainRepositoryContentView {
    func applyMainRepositorySyncConflictSheet(to content: some View) -> some View {
        content.sheet(item: $syncConflictReviewRoutingState.route, content: syncConflictReviewSheet)
    }

    func syncConflictReviewSheet(_ route: SyncConflictReviewRoute) -> some View {
        SyncConflictReviewView(
            model: SyncConflictReviewModel(
                repoPath: route.repoPath,
                conflictID: route.conflictID,
                primaryPath: route.primaryPath,
                conflictDetector: syncConflictsDependencies.syncConflictDetector,
                conflictResolver: syncConflictsDependencies.conflictResolver,
                errorMapper: errorMapper
            ),
            onBackToNeedsReview: { syncConflictReviewRoutingState.route = nil },
            onClose: { syncConflictReviewRoutingState.route = nil },
            onResolved: handleSyncConflictResolved
        )
    }
}

struct SyncConflictReviewRoutingState: Equatable {
    var route: SyncConflictReviewRoute?
}

struct SyncConflictReviewSummarySection: View {
    var conflict: SyncConflictSnapshot

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(conflict.summaryDisplay)
                    .font(.headline)
                SyncConflictReviewMetadataGrid(rows: [
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
}

struct SyncConflictReviewVersionsSection: View {
    var files: [SyncConflictAffectedFileSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("Versions"))
                .font(.headline)
            ForEach(files) { file in
                SyncConflictReviewVersionCard(file: file)
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.versions)
    }
}

private struct SyncConflictReviewVersionCard: View {
    var file: SyncConflictAffectedFileSnapshot

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(file.role.displayName)
                    .font(.headline)
                SyncConflictReviewMetadataGrid(rows: [
                    ("Path", file.path),
                    ("Size", file.sizeDisplay),
                    ("Modified", file.modifiedDisplay),
                    ("Hash", file.hashDisplay),
                    ("Source platform", file.sourceDisplay),
                    (L10n.string("File ID"), file.fileID.map(String.init) ?? L10n.string("Unknown"))
                ])
            }
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.versionCard(fileID: file.id))
    }
}

struct SyncConflictReviewVersionImpactList: View {
    var impacts: [SyncConflictVersionImpactSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SyncConflictReviewCopy.impactTitle)
                .font(.headline)
            ForEach(impacts) { impact in
                VStack(alignment: .leading, spacing: 4) {
                    Text(impact.path)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    SyncConflictReviewMetadataGrid(rows: [
                        ("Role", impact.role.displayName),
                        ("File ID", impact.fileIDDisplay),
                        ("Keep", SyncConflictReviewDisplayValue.yesNo(impact.willKeep)),
                        ("Canonical", SyncConflictReviewDisplayValue.yesNo(impact.willBeCanonical)),
                        ("User visible", SyncConflictReviewDisplayValue.yesNo(impact.willRemainUserVisible)),
                        ("Move to Trash", SyncConflictReviewDisplayValue.yesNo(impact.willMoveToTrash)),
                        ("Recovery target", impact.recoveryDisplay),
                        ("Reason", impact.reasonDisplay)
                    ])
                }
                Divider()
            }
        }
    }
}

struct SyncConflictReviewApplySuccess: View {
    var report: SyncConflictResolveReportSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.string("Resolution applied."), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
            SyncConflictReviewMetadataGrid(rows: [
                ("Conflict ID", report.conflictID),
                ("Status", report.status.displayName),
                ("Change log", report.changeLogAction),
                ("Kept paths", SyncConflictReviewDisplayValue.list(report.keptPaths)),
                ("Retained paths", SyncConflictReviewDisplayValue.list(report.retainedPaths)),
                ("Trashed paths", SyncConflictReviewDisplayValue.list(report.trashedPaths)),
                (L10n.string("Undo token"), report.undoToken ?? L10n.string("None"))
            ])
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.applySuccess)
    }
}

struct SyncConflictReviewMappedFailure: View {
    var title: String
    var mapping: CoreErrorMappingSnapshot

    var body: some View {
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
}

struct SyncConflictReviewMetadataGrid: View {
    var rows: [(String, String)]

    var body: some View {
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
}

enum SyncConflictReviewDisplayValue {
    static func list(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    static func yesNo(_ value: Bool) -> String {
        value ? L10n.string("Yes") : L10n.string("No")
    }
}
