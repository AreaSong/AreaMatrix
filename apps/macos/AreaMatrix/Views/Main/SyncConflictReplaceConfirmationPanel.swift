import SwiftUI

struct SyncConflictReplaceConfirmationPanel: View {
    var preview: SyncConflictResolutionPreviewSnapshot
    var confirmation: SyncConflictReplaceConfirmationSnapshot?
    var disabledReason: String?
    let onConfirm: (Bool) -> Void

    @State private var understandsReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Label("Confirm Replace", systemImage: "lock.shield")
                .font(.headline)
            if let replacePlan = preview.replacePlan {
                replacePlanSummary(replacePlan)
            } else {
                Text("Core did not return a replace plan.")
                    .foregroundStyle(.orange)
            }
            Toggle("I understand this will replace the existing file.", isOn: $understandsReplace)
                .disabled(disabledReason != nil || isConfirmed)
                .accessibilityHint("Required before the replace plan can be confirmed.")
            confirmationStatus
            Button(SyncConflictReviewCopy.replaceConfirmAction, role: .destructive) {
                onConfirm(understandsReplace)
            }
                .disabled(!canConfirm)
                .help(disabledReason ?? "Confirm this Core replace plan before applying Use incoming version.")
                .accessibilityIdentifier(SyncConflictReviewAccessibilityID.replaceConfirm)
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.replaceConfirmation)
    }

    private func replacePlanSummary(_ plan: SyncConflictReplacePlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metadataGrid(rows: [
                ("Conflict item", preview.conflictID),
                ("Old file path", plan.oldPath),
                ("New file path", plan.newPath),
                ("Old hash", hashDisplay(plan.oldHashSha256)),
                ("New hash", hashDisplay(plan.newHashSha256)),
                ("Affected record", plan.affectedFileID.map(String.init) ?? "Unknown"),
                ("Old version will be kept at", backupTargetDisplay(plan)),
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
        if isConfirmed {
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

    private var isConfirmed: Bool {
        confirmation?.previewToken == preview.normalizedPreviewToken
    }

    private var canConfirm: Bool {
        disabledReason == nil && understandsReplace && !isConfirmed
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

    private func backupTargetDisplay(_ plan: SyncConflictReplacePlanSnapshot) -> String {
        if let backupTarget = clean(plan.backupTarget) {
            return backupTarget
        }
        if !preview.plannedTrashPaths.isEmpty {
            return "Trash: \(preview.plannedTrashPaths.joined(separator: ", "))"
        }
        return "Trash or Core safety backup"
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
