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
            Label(L10n.string("Confirm Replace"), systemImage: "lock.shield")
                .font(.headline)
            if let replacePlan = preview.replacePlan {
                replacePlanSummary(replacePlan)
            } else {
                Text(L10n.string("Core did not return a replace plan."))
                    .foregroundStyle(.orange)
            }
            Toggle(L10n.string("I understand this will replace the existing file."), isOn: $understandsReplace)
                .disabled(disabledReason != nil || isConfirmed)
                .accessibilityHint(L10n.string("Required before the replace plan can be confirmed."))
            confirmationStatus
            Button(SyncConflictReviewCopy.replaceConfirmAction, role: .destructive) {
                onConfirm(understandsReplace)
            }
            .disabled(!canConfirm)
            .help(disabledReason ?? L10n.string("Confirm this Core replace plan before applying Use incoming version."))
            .accessibilityIdentifier(SyncConflictReviewAccessibilityID.replaceConfirm)
        }
        .accessibilityIdentifier(SyncConflictReviewAccessibilityID.replaceConfirmation)
    }

    private func replacePlanSummary(_ plan: SyncConflictReplacePlanSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SyncConflictReviewMetadataGrid(rows: [
                ("Conflict item", preview.conflictID),
                ("Old file path", plan.oldPath),
                ("New file path", plan.newPath),
                ("Old hash", hashDisplay(plan.oldHashSha256)),
                ("New hash", hashDisplay(plan.newHashSha256)),
                (L10n.string("Affected record"), plan.affectedFileID.map(String.init) ?? L10n.string("Unknown")),
                ("Old version will be kept at", backupTargetDisplay(plan)),
                ("DB update", plan.databaseUpdate),
                ("Change log", plan.changeLogAction),
                ("Recovery note", plan.recoveryNote)
            ])
            if !preview.hasRecoverableOldVersion {
                Label(
                    L10n.string("Replace requires Trash or a Core safety backup."),
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var confirmationStatus: some View {
        if isConfirmed {
            Label(L10n.string("Replace plan confirmed for this preview token."), systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        } else if let disabledReason {
            Label(disabledReason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            Text(L10n.string("Review the file, DB, backup and change log impact before applying."))
                .foregroundStyle(.secondary)
        }
    }

    private var isConfirmed: Bool {
        confirmation?.previewToken == preview.normalizedPreviewToken
    }

    private var canConfirm: Bool {
        disabledReason == nil && understandsReplace && !isConfirmed
    }

    private func hashDisplay(_ value: String?) -> String {
        guard let value = clean(value) else { return L10n.string("Unknown") }
        return value.count > 8 ? "\(value.prefix(8))..." : value
    }

    private func backupTargetDisplay(_ plan: SyncConflictReplacePlanSnapshot) -> String {
        if let backupTarget = clean(plan.backupTarget) {
            return backupTarget
        }
        if !preview.plannedTrashPaths.isEmpty {
            return L10n.format("syncConflict.replace.trashPaths", preview.plannedTrashPaths.joined(separator: ", "))
        }
        return L10n.string("Trash or Core safety backup")
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
