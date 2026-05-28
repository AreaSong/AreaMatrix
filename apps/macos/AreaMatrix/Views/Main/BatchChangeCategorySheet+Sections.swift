import SwiftUI

extension BatchChangeCategorySheet {
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            summarySection
            targetSection
            previewSection
            resultSection
            actionButtons
        }
    }

    var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Selected: \(selectedCount) files")
            Text("Current categories: \(currentCategoriesText)")
            ForEach(selectedFiles.prefix(5)) { file in
                Text(file.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            BatchChangeCategoryPicker(
                categories: availableCategories,
                filteredCategories: filteredCategories,
                selection: $targetCategory,
                searchText: $categorySearchText,
                isDisabled: isApplying || disabledReason != nil
            )
            Button("Create new category...") {
                onCreateNewCategory(BatchChangeCategoryNewCategoryHandoff(
                    selectedFileIDs: fileIDs,
                    currentTargetCategory: targetCategory
                ))
            }
            .disabled(isApplying || disabledReason != nil)
            .accessibilityIdentifier("S2-12-create-new-category")
            Toggle("Move files into the category folder", isOn: $moveRepoOwnedFiles)
                .disabled(isApplying || disabledReason != nil)
            Text("When off, only AreaMatrix metadata changes. Files stay in their current locations.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var previewSection: some View {
        if previewState.isLoading {
            Label("Previewing changes...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        }
        if let failure = previewState.failure {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                Spacer()
                Button("Retry") { Task { await refreshPreview() } }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        if let preview = previewState.report {
            previewSummary(preview)
        }
        if let reason = disabledReason {
            Label(reason, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    func previewSummary(_ preview: BatchCategoryPreviewReportSnapshot) -> some View {
        let presentation = BatchCategoryPreviewReportPresentation(report: preview)
        return VStack(alignment: .leading, spacing: 6) {
            Text(presentation.moveSummaryText)
            Text(presentation.metadataSummaryText)
            Text(presentation.skippedSummaryText)
            Text(presentation.blockedSummaryText)
            if let reason = preview.applyBlockedReason, !reason.isEmpty {
                Text(reason).foregroundStyle(.secondary)
            }
            Button(showsDetails ? "Hide details" : "Show details") {
                showsDetails.toggle()
            }
            if showsDetails {
                BatchChangeCategoryPreviewTable(items: preview.items)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    var resultSection: some View {
        if let result {
            let presentation = BatchCategoryChangeReportPresentation(report: result)
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.changedSummaryText)
                Text(presentation.skippedSummaryText)
                Text(presentation.failedSummaryText)
                if result.failedCount > 0 {
                    failureResultDetails(for: result)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
        if let failure {
            Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func failureResultDetails(for report: BatchCategoryChangeReportSnapshot) -> some View {
        Button("View details") { showsDetails.toggle() }
        if showsDetails {
            ForEach(report.itemResults.filter { $0.status == .failed }) { item in
                Text("File \(item.fileID): \(item.error ?? "Failed")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var actionButtons: some View {
        HStack {
            Button("Preview") { Task { await refreshPreview(expandDetails: true) } }
                .disabled(isApplying || targetCategory.isEmpty || disabledReason != nil)
            Spacer()
            Button("Cancel", action: onClose)
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)
            Button(isApplying ? "Applying..." : "Apply") {
                Task { await apply() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
            .accessibilityIdentifier("S2-12-batch-change-category-apply")
        }
    }
}
