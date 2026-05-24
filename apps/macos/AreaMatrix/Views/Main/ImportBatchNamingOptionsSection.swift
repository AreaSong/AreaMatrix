import SwiftUI

struct ImportBatchNamingOptionsSection: View {
    @Binding var selectedStrategy: ImportBatchNamingStrategy
    @Binding var prefix: String
    let isDisabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("命名策略", selection: $selectedStrategy) {
                ForEach(ImportBatchNamingStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isDisabled)

            if selectedStrategy == .uniformPrefix {
                TextField("统一前缀", text: $prefix)
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
            Picker("Strategy", selection: $draft.mode) {
                ForEach(BatchRenameModeSnapshot.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isDisabled)
            .accessibilityIdentifier("S2-14-rename-strategy")
            fields
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch draft.mode {
        case .prefix:
            TextField("Prefix", text: $draft.prefix).textFieldStyle(.roundedBorder)
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
            Picker("Date source", selection: $draft.dateSource) {
                ForEach(BatchRenameDateSourceSnapshot.allCases) { Text($0.rawValue).tag($0) }
            }
            TextField("Date format", text: $draft.dateFormat).textFieldStyle(.roundedBorder)
            TextField("Separator", text: $draft.separator).textFieldStyle(.roundedBorder).frame(width: 90)
        }
        .disabled(isDisabled)
    }
}

private struct SequenceFields: View {
    @Binding var draft: BatchRenameRuleDraft
    let isDisabled: Bool

    var body: some View {
        HStack {
            TextField("Separator", text: $draft.separator).textFieldStyle(.roundedBorder).frame(width: 120)
            Stepper("Start \(draft.startNumber)", value: $draft.startNumber, in: 0...999_999)
            Stepper("Padding \(draft.padding)", value: $draft.padding, in: 1...12)
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
                TextField("Find", text: $draft.find).textFieldStyle(.roundedBorder)
                TextField("Replace with", text: $draft.replacement).textFieldStyle(.roundedBorder)
            }
            Toggle("Case sensitive", isOn: $draft.caseSensitive)
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
                Label("Refreshing preview...", systemImage: "arrow.triangle.2.circlepath")
            }
            if let previewFailure = previewState.failure {
                Label(
                    "Could not preview rename: \(previewFailure.userMessage)",
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
    let preview: BatchRenamePreviewReportSnapshot

    var body: some View {
        let presentation = BatchRenamePreviewReportPresentation(report: preview)
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.renameSummaryText)
            Text(presentation.displayOnlySummaryText)
            Text(presentation.unchangedSummaryText)
            Text(presentation.blockedSummaryText)
            Text(presentation.conflictSummaryText)
            if let reason = preview.applyBlockedReason, !reason.isEmpty {
                Text(reason)
            }
            BatchRenamePreviewTable(items: preview.items)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

private struct BatchRenamePreviewTable: View {
    let items: [BatchRenamePreviewItemSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Original -> New | Status").font(.caption.weight(.semibold))
            ForEach(items) { item in
                Text(rowText(item)).font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func rowText(_ item: BatchRenamePreviewItemSnapshot) -> String {
        let original = item.originalName ?? item.currentPath ?? "File \(item.fileID)"
        let reason = item.reason.map { " - \($0)" } ?? ""
        return "\(original) -> \(item.newName ?? "-") | \(item.status.rawValue)\(reason)"
    }
}

struct BatchRenameResultSummary: View {
    let result: BatchRenameReportSnapshot?

    var body: some View {
        if let result {
            let presentation = BatchRenameReportPresentation(report: result)
            VStack(alignment: .leading, spacing: 6) {
                Text(presentation.renamedSummaryText)
                Text(presentation.unchangedSummaryText)
                Text(presentation.failedSummaryText)
                ForEach(result.itemResults.filter { $0.status == .failed }) { item in
                    Text("File \(item.fileID): \(item.error ?? "Failed")").font(.caption)
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct BatchRenamePreviewReportPresentation: Equatable {
    var renameSummaryText: String
    var displayOnlySummaryText: String
    var unchangedSummaryText: String
    var blockedSummaryText: String
    var conflictSummaryText: String

    init(report: BatchRenamePreviewReportSnapshot) {
        renameSummaryText = "\(Self.itemText(report.willRenameCount)) will rename files"
        displayOnlySummaryText = "\(Self.itemText(report.displayOnlyCount)) will update display names"
        unchangedSummaryText = "\(Self.itemText(report.unchangedCount)) unchanged"
        blockedSummaryText = "\(Self.itemText(report.blockedCount)) blocked"
        conflictSummaryText = "\(Self.itemText(report.conflictCount)) conflicts"
    }

    private static func itemText(_ count: Int64) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

struct BatchRenameReportPresentation: Equatable {
    var renamedSummaryText: String
    var unchangedSummaryText: String
    var failedSummaryText: String

    init(report: BatchRenameReportSnapshot) {
        renamedSummaryText = "\(Self.itemText(report.successfulRenameCount)) renamed"
        unchangedSummaryText = "\(Self.itemText(report.unchangedCount + report.skippedCount)) skipped or unchanged"
        failedSummaryText = "\(Self.itemText(report.failedCount)) failed"
    }

    private static func itemText(_ count: Int64) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}
