import SwiftUI

extension ICloudConflictMinimalSheet {
    var versionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(versionListTitle)
                .font(.headline)
            ForEach(model.previewVersions) { version in
                versionRow(version)
            }
        }
    }

    func versionRow(_ version: ICloudConflictVersionMetadataSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            metadataRow(version.role.displayName, version.displayName)
            metadataRow("Path", version.path.isEmpty ? "Unknown path" : version.path)
            metadataRow("Modified", modifiedLabel(for: version.modifiedAt))
            metadataRow("Size", sizeLabel(for: version.sizeBytes))
            metadataRow("Hash", version.hashDisplay)
            metadataRow("Preview", version.previewDisplay)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    var previewStatus: some View {
        switch model.previewState {
        case .notLoaded, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading conflict details...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("icloud-conflict-review-icloud-conflict-visual-loading")
        case let .loaded(preview):
            VStack(alignment: .leading, spacing: 5) {
                statusLabel("Conflict details loaded", systemImage: "checkmark.circle", color: .green)
                if let blockedReason = preview.blockedReason, !blockedReason.isEmpty {
                    statusLabel(blockedReason, systemImage: "exclamationmark.triangle", color: .orange)
                }
                if !preview.metadataComplete {
                    statusLabel(
                        "Metadata is incomplete; destructive resolution is disabled.",
                        systemImage: "info.circle",
                        color: .orange
                    )
                }
                if !preview.trashAvailable {
                    statusLabel(
                        "Trash is unavailable; Keep left/right are disabled.",
                        systemImage: "trash.slash",
                        color: .orange
                    )
                }
            }
            .accessibilityIdentifier("icloud-conflict-review-icloud-conflict-visual-preview-loaded")
        case .empty:
            VStack(alignment: .leading, spacing: 8) {
                statusLabel("Conflict no longer exists", systemImage: "exclamationmark.triangle", color: .orange)
                Button("Refresh") {
                    Task { await model.loadPreview() }
                }
            }
            .accessibilityIdentifier("icloud-conflict-review-icloud-conflict-visual-empty")
        case let .failed(mapping):
            mappedPreviewError(mapping)
        }
    }

    func mappedPreviewError(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLabel(
                L10n.format("iCloudConflict.detail.failed", mapping.kind.rawValue),
                systemImage: "exclamationmark.triangle",
                color: .red
            )
            Text(mapping.userMessage)
                .font(.caption)
            Text(mapping.suggestedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.format(
                "syncConflict.error.severityRecoverability",
                mapping.severity.rawValue,
                mapping.recoverability.rawValue
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            if !mapping.rawContext.isEmpty {
                Text(mapping.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            Button("Retry") {
                Task { await model.loadPreview() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("icloud-conflict-review-icloud-conflict-visual-preview-error")
    }

    @ViewBuilder
    var validationStatus: some View {
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
        case let .ready(validation, warnings):
            VStack(alignment: .leading, spacing: 5) {
                statusLabel("Repository path validated", systemImage: "checkmark.circle", color: .green)
                metadataRow("Repository", validation.repoPath)
                ForEach(warnings, id: \.self) { warning in
                    statusLabel(warning, systemImage: "icloud", color: .orange)
                }
            }
        case let .blocked(validation, reasons):
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
        case let .failed(mapping):
            mappedErrorStatus(mapping)
        }
    }

    func mappedErrorStatus(_ mapping: CoreErrorMappingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            statusLabel(
                L10n.format("iCloudConflict.repositoryCheck.failed", mapping.kind.rawValue),
                systemImage: "exclamationmark.triangle",
                color: .red
            )
            Text(mapping.userMessage)
                .font(.caption)
            Text(mapping.suggestedAction)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L10n.format(
                "syncConflict.error.severityRecoverability",
                mapping.severity.rawValue,
                mapping.recoverability.rawValue
            ))
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
            .accessibilityIdentifier("icloud-conflict-minimal-error-mapping-retry-repository-check")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("icloud-conflict-minimal-error-mapping-error-mapping")
    }

    @ViewBuilder
    var resolutionCapabilityStatus: some View {
        if let blocker = resolutionCapability.blocker {
            VStack(alignment: .leading, spacing: 6) {
                statusLabel(blocker.title, systemImage: "exclamationmark.triangle", color: .orange)
                Text(blocker.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(blocker.suggestedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(blocker.rawContext)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .accessibilityIdentifier("icloud-conflict-minimal-core-resolution-blocked")
        }
    }

    var strategyOptions: some View {
        Picker("Resolution", selection: $selectedStrategy) {
            ForEach(ICloudConflictResolutionStrategy.allCases) { strategy in
                Text(strategy.title).tag(strategy)
            }
        }
        .pickerStyle(.radioGroup)
        .disabled(currentResolutionState.isApplying || model.previewState.isLoading)
        .onChange(of: selectedStrategy) { _, newValue in
            if !newValue.requiresSecondConfirmation { didConfirmSingleVersion = false }
        }
    }
}
