import SwiftUI

struct SyncConflictReplaceConfirmationPanel: View {
    var preview: SyncConflictResolutionPreviewSnapshot
    var confirmation: SyncConflictReplaceConfirmationSnapshot?
    var disabledReason: String?
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label("Replace confirmation", systemImage: "lock.shield")
                .font(.headline)
            if let replacePlan = preview.replacePlan {
                replacePlanSummary(replacePlan)
            } else {
                Text("Core did not return a replace plan.")
                    .foregroundStyle(.orange)
            }
            confirmationStatus
            Button(SyncConflictReviewCopy.replaceConfirmAction, role: .destructive, action: onConfirm)
                .disabled(disabledReason != nil)
                .help(disabledReason ?? "Confirm this Core replace plan before applying Use incoming version.")
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.replaceConfirm)
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.replaceConfirmation)
    }

    private func replacePlanSummary(_ plan: SyncConflictReplacePlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataGrid(rows: [
                ("Existing path", plan.oldPath),
                ("Incoming path", plan.newPath),
                ("Existing hash", hashDisplay(plan.oldHashSha256)),
                ("Incoming hash", hashDisplay(plan.newHashSha256)),
                ("Affected record", plan.affectedFileID.map(String.init) ?? "Unknown"),
                ("Backup target", clean(plan.backupTarget) ?? "Trash or Core safety backup"),
                ("DB update", plan.databaseUpdate),
                ("Change log", plan.changeLogAction),
                ("Recovery note", plan.recoveryNote)
            ])
            if preview.trashRequired, !preview.trashAvailable {
                Label("Replace requires Trash or a Core safety backup.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var confirmationStatus: some View {
        if let confirmation, confirmation.previewToken == preview.normalizedPreviewToken {
            Label("Replace plan confirmed for this preview token.", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        } else if let disabledReason {
            Label(disabledReason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            Text("Review the file, DB, backup and change log impact before applying.")
                .foregroundStyle(.secondary)
        }
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

    private func hashDisplay(_ value: String?) -> String {
        guard let value = clean(value) else { return "Unknown" }
        return value.count > 8 ? "\(value.prefix(8))..." : value
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
