import AreaMatrixFeatureIngestion
import AreaMatrixFeatureOperation
import SwiftUI

extension ImportBatchNamingStrategy {
    var title: String {
        switch self {
        case .suggestedName:
            L10n.string("使用建议命名")
        case .originalName:
            L10n.string("保留原名")
        case .normalizedCharacters:
            L10n.string("仅标准化字符")
        case .uniformPrefix:
            L10n.string("统一前缀")
        }
    }
}

struct ImportBatchNamingOptionsSection: View {
    @Binding var selectedStrategy: ImportBatchNamingStrategy
    @Binding var prefix: String
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.string("命名策略"), selection: $selectedStrategy) {
                ForEach(ImportBatchNamingStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isDisabled)

            if selectedStrategy == .uniformPrefix {
                TextField(L10n.string("统一前缀"), text: $prefix)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 260)
                    .disabled(isDisabled)
            }
        }
    }
}

struct RenameRuleEditor: View {
    @Binding var draft: BatchRenameRuleDraft
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(L10n.string("Strategy"), selection: $draft.mode) {
                ForEach(BatchRenameModeSnapshot.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isDisabled)
            .accessibilityIdentifier("batch-rename-rename-strategy")
            fields
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch draft.mode {
        case .prefix:
            TextField(L10n.string("Prefix"), text: $draft.prefix).textFieldStyle(.roundedBorder)
        case .datePrefix:
            DatePrefixFields(draft: $draft, isDisabled: isDisabled)
        case .keepBaseSequence:
            SequenceFields(draft: $draft, isDisabled: isDisabled)
        case .replaceText:
            ReplaceTextFields(draft: $draft, isDisabled: isDisabled)
        }
    }
}

private struct DatePrefixFields: View {
    @Binding var draft: BatchRenameRuleDraft
    let isDisabled: Bool

    var body: some View {
        HStack {
            Picker(L10n.string("Date source"), selection: $draft.dateSource) {
                ForEach(BatchRenameDateSourceSnapshot.allCases) { Text($0.displayName).tag($0) }
            }
            TextField(L10n.string("Date format"), text: $draft.dateFormat).textFieldStyle(.roundedBorder)
            TextField(L10n.string("Separator"), text: $draft.separator).textFieldStyle(.roundedBorder).frame(width: 90)
        }
        .disabled(isDisabled)
    }
}

private struct SequenceFields: View {
    @Binding var draft: BatchRenameRuleDraft
    let isDisabled: Bool

    var body: some View {
        HStack {
            TextField(L10n.string("Separator"), text: $draft.separator).textFieldStyle(.roundedBorder).frame(width: 120)
            Stepper(
                L10n.format("import.batch-naming.start-number", Int64(draft.startNumber)),
                value: $draft.startNumber,
                in: 0 ... 999_999
            )
            Stepper(
                L10n.format("import.batch-naming.padding", Int64(draft.padding)),
                value: $draft.padding,
                in: 1 ... 12
            )
        }
        .disabled(isDisabled)
    }
}

private struct ReplaceTextFields: View {
    @Binding var draft: BatchRenameRuleDraft
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.string("Find"), text: $draft.find).textFieldStyle(.roundedBorder)
                TextField(L10n.string("Replace with"), text: $draft.replacement).textFieldStyle(.roundedBorder)
            }
            Toggle(L10n.string("Case sensitive"), isOn: $draft.caseSensitive)
        }
        .disabled(isDisabled)
    }
}

struct BatchRenamePreviewSection: View {
    let previewState: BatchRenamePreviewState
    let validationMessage: String?
    let failure: CoreErrorMappingSnapshot?
    let disabledReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if previewState.isLoading {
                Label(L10n.string("Refreshing preview..."), systemImage: "arrow.triangle.2.circlepath")
            }
            if let previewFailure = previewState.failure {
                Label(
                    L10n.format("import.batch-naming.preview-failed", previewFailure.userMessage),
                    systemImage: "exclamationmark.triangle"
                )
            }
            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle").font(.caption)
            }
            if let failure {
                Label(failure.userMessage, systemImage: "exclamationmark.triangle")
            }
            if let preview = previewState.displayReport {
                BatchRenamePreviewSummary(preview: preview)
            }
            if let disabledReason {
                Label(disabledReason, systemImage: "exclamationmark.triangle").font(.caption)
            }
        }
        .foregroundStyle(.secondary)
    }
}

private struct BatchRenamePreviewSummary: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let preview: BatchRenamePreviewReportSnapshot

    var body: some View {
        let presentation = BatchRenamePreviewReportPresentation(report: preview)
        NeutralSummaryPanel {
            VStack(alignment: .leading, spacing: 6) {
                Text(localizer.resolve(presentation.renameSummaryText))
                Text(localizer.resolve(presentation.displayOnlySummaryText))
                Text(localizer.resolve(presentation.unchangedSummaryText))
                Text(localizer.resolve(presentation.blockedSummaryText))
                Text(localizer.resolve(presentation.conflictSummaryText))
                if let reason = preview.applyBlockedReason, !reason.isEmpty {
                    Text(reason)
                }
                BatchRenamePreviewTable(items: preview.items)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct BatchRenamePreviewTable: View {
    let items: [BatchRenamePreviewItemSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string("Original -> New | Status")).font(.caption.weight(.semibold))
            ForEach(items) { item in
                Text(rowText(item)).font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func rowText(_ item: BatchRenamePreviewItemSnapshot) -> String {
        let original = item.originalName ?? item.currentPath ?? L10n.format("File %lld", item.fileID)
        let reason = item.reason.map { " - \($0)" } ?? ""
        return "\(original) -> \(item.newName ?? "-") | \(item.status.displayName)\(reason)"
    }
}

struct BatchRenameResultSummary: View {
    @EnvironmentObject private var localizer: AppLocalizer
    let result: BatchRenameReportSnapshot?

    var body: some View {
        if let result {
            let presentation = BatchRenameReportPresentation(report: result)
            NeutralSummaryPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizer.resolve(presentation.renamedSummaryText))
                    Text(localizer.resolve(presentation.unchangedSummaryText))
                    Text(localizer.resolve(presentation.failedSummaryText))
                    ForEach(result.itemResults.filter { $0.status == .failed }) { item in
                        Text(
                            L10n.format(
                                "import.common.file-error",
                                item.fileID,
                                item.error ?? L10n.string("Failed")
                            )
                        ).font(.caption)
                    }
                }
            }
        }
    }
}

struct BatchRenamePreviewReportPresentation: Equatable {
    var renameSummaryText: LocalizedMessage
    var displayOnlySummaryText: LocalizedMessage
    var unchangedSummaryText: LocalizedMessage
    var blockedSummaryText: LocalizedMessage
    var conflictSummaryText: LocalizedMessage

    init(report: BatchRenamePreviewReportSnapshot) {
        renameSummaryText = L10n.pluralMessage("import.batch-naming.preview.will-rename", count: report.willRenameCount)
        displayOnlySummaryText = L10n.pluralMessage(
            "import.batch-naming.preview.display-only",
            count: report.displayOnlyCount
        )
        unchangedSummaryText = L10n.pluralMessage("import.batch-naming.preview.unchanged", count: report.unchangedCount)
        blockedSummaryText = L10n.pluralMessage("import.batch-naming.preview.blocked", count: report.blockedCount)
        conflictSummaryText = L10n.pluralMessage("import.batch-naming.preview.conflicts", count: report.conflictCount)
    }
}

struct BatchRenameReportPresentation: Equatable {
    var renamedSummaryText: LocalizedMessage
    var unchangedSummaryText: LocalizedMessage
    var failedSummaryText: LocalizedMessage

    init(report: BatchRenameReportSnapshot) {
        renamedSummaryText = L10n.pluralMessage(
            "import.batch-naming.result.renamed",
            count: report.successfulRenameCount
        )
        unchangedSummaryText = L10n.pluralMessage(
            "import.batch-naming.result.skipped-or-unchanged",
            count: report.unchangedCount + report.skippedCount
        )
        failedSummaryText = L10n.pluralMessage("import.batch-naming.result.failed", count: report.failedCount)
    }
}
