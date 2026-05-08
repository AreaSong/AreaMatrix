import SwiftUI

struct ICloudConflictMinimalSheet: View {
    let isTrashAvailable: Bool
    let onCancel: () -> Void
    let onApplyKeepBoth: () -> Void
    @StateObject private var model: ICloudConflictMinimalModel

    init(
        model: ICloudConflictMinimalModel,
        isTrashAvailable: Bool,
        onCancel: @escaping () -> Void,
        onApplyKeepBoth: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: model)
        self.isTrashAvailable = isTrashAvailable
        self.onCancel = onCancel
        self.onApplyKeepBoth = onApplyKeepBoth
    }

    var body: some View {
        MainFileActionSheetContainer(title: "Resolve iCloud Conflict", pageID: "S1-25") {
            VStack(alignment: .leading, spacing: 12) {
                Text("This is an iCloud conflicted copy. AreaMatrix will not delete any version automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                versionList
                validationStatus
                keepBothOption
                singleVersionDisabledNote
                actionButtons
            }
            .task {
                await model.validateRepositoryPath()
            }
        }
    }

    private var versionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Versions")
                .font(.headline)
            versionRow(model.originalVersion)
            versionRow(model.conflictedCopyVersion)
        }
    }

    private func versionRow(_ version: ICloudConflictVersionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            metadataRow(version.role == .original ? "Original" : "Conflicted copy", version.displayName)
            metadataRow("Path", version.pathLabel)
            metadataRow("Modified", modifiedLabel(for: version.modifiedAt))
            metadataRow("Size", sizeLabel(for: version.sizeBytes))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var validationStatus: some View {
        switch model.repositoryValidationState {
        case .notChecked:
            statusLabel("Repository path not checked", systemImage: "clock", color: .secondary)
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking repository path...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .ready(let validation, let warnings):
            VStack(alignment: .leading, spacing: 5) {
                statusLabel("Repository path validated", systemImage: "checkmark.circle", color: .green)
                metadataRow("Repository", validation.repoPath)
                ForEach(warnings, id: \.self) { warning in
                    statusLabel(warning, systemImage: "icloud", color: .orange)
                }
            }
        case .blocked(let validation, let reasons):
            VStack(alignment: .leading, spacing: 6) {
                statusLabel("Repository path blocks Apply", systemImage: "exclamationmark.triangle", color: .orange)
                metadataRow("Repository", validation.repoPath)
                ForEach(reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Retry repository check") {
                    Task { await model.validateRepositoryPath() }
                }
            }
        case .failed(let mapping):
            mappedErrorStatus(mapping)
        }
    }

    private func mappedErrorStatus(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLabel(
                "Repository check failed: \(mapping.kind.rawValue)",
                systemImage: "exclamationmark.triangle",
                color: .red
            )
            Text(mapping.userMessage)
                .font(.caption)
            Text(mapping.suggestedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Severity: \(mapping.severity.rawValue); Recoverability: \(mapping.recoverability.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !mapping.rawContext.isEmpty {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button("Retry repository check") {
                Task { await model.validateRepositoryPath() }
            }
            .accessibilityIdentifier("S1-25-C1-21-retry-repository-check")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("S1-25-C1-21-error-mapping")
    }

    private var keepBothOption: some View {
        Label("保留两份（推荐）", systemImage: "checkmark.circle")
            .font(.body.weight(.medium))
            .foregroundStyle(model.canApplyKeepBoth ? .primary : .secondary)
    }

    @ViewBuilder
    private var singleVersionDisabledNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("This action keeps both versions and does not move files.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !isTrashAvailable {
                Text("Single-version resolution requires system Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(model.repositoryValidationState.isChecking)
            Button("Apply", action: onApplyKeepBoth)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canApplyKeepBoth)
        }
    }

    private func statusLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func modifiedLabel(for timestamp: Int64?) -> String {
        guard let timestamp else { return "Unknown" }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened)
    }

    private func sizeLabel(for bytes: Int64?) -> String {
        guard let bytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
