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
            Text(L10n.plural("file-actions.change-category.selected-files", count: selectedCount))
            Text(L10n.format("file-actions.change-category.current-categories", currentCategoriesText))
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
            Button(L10n.string("Create new category...")) {
                onCreateNewCategory(BatchChangeCategoryNewCategoryHandoff(
                    selectedFileIDs: fileIDs,
                    currentTargetCategory: targetCategory
                ))
            }
            .disabled(isApplying || disabledReason != nil)
            .accessibilityIdentifier("batch-change-category-create-new-category")
            Toggle(L10n.string("Move files into the category folder"), isOn: $moveRepoOwnedFiles)
                .disabled(isApplying || disabledReason != nil)
            Text(L10n.string("When off, only AreaMatrix metadata changes. Files stay in their current locations."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var previewSection: some View {
        if previewState.isLoading {
            Label(L10n.string("Previewing changes..."), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        }
        if let failure = previewState.failure {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                Spacer()
                Button(L10n.string("Retry")) { Task { await refreshPreview() } }
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
        return NeutralSummaryPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(localizer.resolve(presentation.moveSummaryText))
                Text(localizer.resolve(presentation.metadataSummaryText))
                Text(localizer.resolve(presentation.skippedSummaryText))
                Text(localizer.resolve(presentation.blockedSummaryText))
                if let reason = preview.applyBlockedReason, !reason.isEmpty {
                    Text(reason).foregroundStyle(.secondary)
                }
                Button(showsDetails ? L10n.string("Hide details") : L10n.string("Show details")) {
                    showsDetails.toggle()
                }
                if showsDetails {
                    BatchChangeCategoryPreviewTable(items: preview.items)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    var resultSection: some View {
        if let result {
            let presentation = BatchCategoryChangeReportPresentation(report: result)
            NeutralSummaryPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizer.resolve(presentation.changedSummaryText))
                    Text(localizer.resolve(presentation.skippedSummaryText))
                    Text(localizer.resolve(presentation.failedSummaryText))
                    if result.failedCount > 0 {
                        failureResultDetails(for: result)
                    }
                }
            }
        }
        if let failure {
            Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func failureResultDetails(for report: BatchCategoryChangeReportSnapshot) -> some View {
        Button(L10n.string("View details")) { showsDetails.toggle() }
        if showsDetails {
            ForEach(report.itemResults.filter { $0.status == .failed }) { item in
                Text(
                    L10n.format(
                        "file-actions.common.file-error",
                        item.fileID,
                        item.error ?? L10n.string("Failed")
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    var actionButtons: some View {
        HStack {
            Button(L10n.string("Preview")) { Task { await refreshPreview(expandDetails: true) } }
                .disabled(isApplying || targetCategory.isEmpty || disabledReason != nil)
            Spacer()
            Button(L10n.string("Cancel"), action: onClose)
                .keyboardShortcut(.cancelAction)
                .disabled(isApplying)
            Button(isApplying ? L10n.string("Applying...") : L10n.string("Apply")) {
                Task { await apply() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
            .accessibilityIdentifier("batch-change-category-batch-change-category-apply")
        }
    }
}
