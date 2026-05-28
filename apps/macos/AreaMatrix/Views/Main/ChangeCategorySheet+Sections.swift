import SwiftUI

extension ChangeCategorySheet {
    @ViewBuilder
    var classifierReasonRow: some View {
        if mode == .classifierCorrection, let file {
            classifierReasonRow(for: file)
        }
    }

    @ViewBuilder
    func classifierReasonRow(for file: FileEntrySnapshot) -> some View {
        if let result = classifierContextState.result(for: file.id) {
            metadataRow("Classification source", classificationReasonText(result))
        } else if classifierContextState.isLoading(classifierContextRequest(for: file)) {
            metadataRow("Classification source", "Loading classification...")
        } else if let failure = classifierContextState.failure(for: file.id) {
            metadataRow("Classification source", "Cannot load classification: \(failure.userMessage)")
        } else {
            metadataRow("Classification source", "Loading classification...")
        }
    }

    @ViewBuilder
    func classifierOptions(for file: FileEntrySnapshot) -> some View {
        if mode == .classifierCorrection {
            Toggle("Move file to the new category folder", isOn: $moveFile)
                .disabled(!canToggleMoveFile(for: file) || state.isMoving(fileID: file.id))
            if !canToggleMoveFile(for: file) {
                Text(moveDisabledReason(for: file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("Remember this correction as a rule", isOn: $rememberCorrection)
                .disabled(state.isMoving(fileID: file.id))
            if rememberCorrection {
                ruleSuggestionPanel(for: file)
            }
        }
    }

    func ruleSuggestionPanel(for file: FileEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rule suggestions")
                .font(.callout.weight(.semibold))
            Text(ruleSuggestionText(for: file))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Apply correction changes only this file. Save a rule from Edit rule or Preview impact.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                ruleHandoffSubmitButton("Edit rule...", file: file, destination: .saveRule)
                ruleHandoffSubmitButton("Preview impact", file: file, destination: .impactPreview)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    func targetPathText(for file: FileEntrySnapshot) -> String {
        let request = previewRequest(for: file)
        if let preview = state.preview(for: request) {
            return preview.targetPath
        }
        if targetCategory == file.category {
            return file.path
        }
        if state.isChecking(request) {
            return "Checking destination..."
        }
        if mode == .classifierCorrection {
            return "Select a category to preview the Core target path."
        }
        return "\(targetCategory)/\(file.currentName)"
    }

    @ViewBuilder
    func statusView(for file: FileEntrySnapshot) -> some View {
        let request = previewRequest(for: file)
        if targetCategory == file.category {
            statusLabel("Choose a different category", systemImage: "info.circle", color: .secondary)
        } else if state.isChecking(request) {
            statusLabel("Checking destination...", systemImage: "arrow.triangle.2.circlepath", color: .secondary)
        } else if state.isMoving(fileID: file.id) {
            statusLabel("Moving...", systemImage: "arrow.triangle.2.circlepath", color: .secondary)
        } else if let failure = state.failure(for: file.id, targetCategory: targetCategory) {
            failureView(failure, file: file)
        } else if let preview = state.preview(for: request) {
            previewStatus(preview)
        }
    }

    func actionButtons(for file: FileEntrySnapshot) -> some View {
        HStack {
            if mode == .classifierCorrection, rememberCorrection {
                ruleHandoffSubmitButton("Edit rule...", file: file, destination: .saveRule)
                ruleHandoffSubmitButton("Preview impact", file: file, destination: .impactPreview)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .disabled(state.isMoving(fileID: file.id))
            Button(primaryActionTitle(for: file)) {
                onChangeCategory(file.id, targetCategory, mode, classifierOptions)
            }
            .disabled(actionDisabled(for: file))
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("\(pageID)-apply")
        }
    }

    func failureView(_ failure: CoreErrorMappingSnapshot, file: FileEntrySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(failureMessage(failure, file: file), systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(failure.suggestedAction)
                .font(.caption)
            Text(failure.rawContext)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            failureActions(failure, file: file)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(Color.yellow.opacity(0.12))
    }

    func failureActions(_ failure: CoreErrorMappingSnapshot, file: FileEntrySnapshot) -> some View {
        HStack {
            if hasUnresolvedNameConflict(for: file) {
                Button("Rename first") {
                    onRenameFirst(file.id, targetCategory)
                }
            }
            if failure.kind == .permissionDenied {
                Button("Open folder permissions", action: onOpenPermissionRecovery)
            }
            if state.failureOperation(for: file.id, targetCategory: targetCategory) == .preview {
                Button("Retry preview") {
                    onPreview(file.id, targetCategory)
                }
            }
            Button("Collect Diagnostics...", action: onCollectDiagnostics)
        }
    }

    func previewStatus(_ preview: MoveToCategoryPreviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if preview.indexOnly {
                statusLabel(
                    "Index-only: AreaMatrix updates category metadata and change log only.",
                    systemImage: "link",
                    color: .secondary
                )
            } else if preview.nameConflictResolved {
                statusLabel(
                    "Target name exists. AreaMatrix will use \(preview.targetName).",
                    systemImage: "number",
                    color: .secondary
                )
            } else {
                statusLabel("No conflict at target location", systemImage: "checkmark.circle", color: .green)
            }
        }
    }
}
