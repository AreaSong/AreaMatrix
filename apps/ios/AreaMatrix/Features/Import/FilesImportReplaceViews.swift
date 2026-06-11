import SwiftUI

struct FilesImportConflictCandidateRow: View {
    let candidate: FilesImportReplaceCandidate
    let replaceUnavailableReason: String?
    let onSelectStrategy: (FilesImportReplaceCandidate.ID, FilesImportConflictStrategy) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(candidate.kind.title, systemImage: "exclamationmark.triangle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
            Text("\(candidate.incomingName) conflicts with \(candidate.existingPath).")
                .font(.caption)
            Text(candidate.safeResolutionSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let replaceBlockedReason = candidate.replaceBlockedReason {
                Text(replaceBlockedReason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            actionButtons
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.kind.title), \(candidate.safeResolutionSummary)")
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack {
            ForEach(candidate.kind.availableStrategies) { strategy in
                Button(strategy.title) {
                    onSelectStrategy(candidate.id, strategy)
                }
                .buttonStyle(.bordered)
                .tint(strategy == .replace ? .red : nil)
                .disabled(strategy == .replace && replaceUnavailableReason != nil)
                .accessibilityHint(strategy.detail)
            }
        }
        if let replaceUnavailableReason {
            Text(replaceUnavailableReason)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

struct FilesImportReplaceConfirmSheet: View {
    let confirmation: FilesImportReplaceConfirmation
    let errorMessage: String?
    let onCancel: () -> Void
    let onConfirm: (Bool) -> Void

    @State private var understandsReplace = false

    var body: some View {
        NavigationStack {
            List {
                Section("Replace plan") {
                    LabeledContent("Existing file", value: confirmation.candidate.existingPath)
                    LabeledContent("Incoming file", value: confirmation.candidate.incomingPath)
                    LabeledContent("Target", value: confirmation.candidate.targetRelativePath)
                    LabeledContent("Existing hash", value: confirmation.plan.oldHashSHA256 ?? "Unavailable")
                    LabeledContent("Incoming hash", value: confirmation.plan.newHashSHA256 ?? "Unavailable")
                    LabeledContent("Affected record", value: "\(confirmation.plan.affectedFileID)")
                    LabeledContent("Backup target", value: confirmation.plan.backupTarget)
                    LabeledContent("Change log", value: confirmation.plan.changeLogAction)
                    Text(confirmation.plan.databaseUpdate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(confirmation.plan.recoveryNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("I understand this will replace the existing file.", isOn: $understandsReplace)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Confirm Replace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace", role: .destructive) {
                        onConfirm(understandsReplace)
                    }
                    .disabled(!understandsReplace)
                }
            }
        }
    }
}
