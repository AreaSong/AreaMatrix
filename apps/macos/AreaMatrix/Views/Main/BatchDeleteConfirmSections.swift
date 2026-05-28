import SwiftUI

struct BatchDeletePreviewSummary: View {
    let preview: BatchDeletePreviewReportSnapshot
    let showsDetails: Bool
    let onToggleDetails: () -> Void

    var body: some View {
        let presentation = BatchDeletePreviewReportPresentation(report: preview)
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.trashSummaryText)
            Text(presentation.indexOnlySummaryText)
            Text("\(preview.missingCount) missing items can be removed from the index")
            Text(presentation.blockedSummaryText)
            Text(presentation.undoSummaryText)
            Text(presentation.safetySummaryText)
            availabilityWarnings
            if let reason = preview.applyBlockedReason, !reason.isEmpty {
                Text(reason).foregroundStyle(.secondary)
            }
            Button(showsDetails ? "Hide details" : "View details", action: onToggleDetails)
            previewRows
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var availabilityWarnings: some View {
        if !preview.trashAvailable {
            Label(
                [
                    "Trash is not available for this location.",
                    "AreaMatrix will not permanently delete these files in Stage 2."
                ].joined(separator: " "),
                systemImage: "trash.slash"
            )
        }
        if preview.blockedCount > 0 {
            Label("Blocked items will be left unchanged.", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var previewRows: some View {
        if showsDetails {
            BatchDeletePreviewTable(items: preview.items)
        } else {
            BatchDeletePreviewTable(items: Array(preview.items.prefix(8)))
            if preview.items.count > 8 {
                Text("+\(preview.items.count - 8) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct BatchDeleteResultSummary: View {
    let result: BatchDeleteReportSnapshot
    let showsDetails: Bool
    let onToggleDetails: () -> Void

    var body: some View {
        let presentation = BatchDeleteReportPresentation(report: result)
        VStack(alignment: .leading, spacing: 6) {
            Text(presentation.successSummaryText)
            Text(presentation.skippedSummaryText)
            Text(presentation.failedSummaryText)
            Text(presentation.undoSummaryText)
            failedDetails
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var failedDetails: some View {
        if result.failedCount > 0 {
            Button("View details", action: onToggleDetails)
            if showsDetails {
                ForEach(result.itemResults.filter { $0.status == .failed }) { item in
                    Text("File \(item.fileID): \(item.error ?? "Failed")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BatchDeletePreviewTable: View {
    let items: [BatchDeletePreviewItemSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                Text(rowText(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func rowText(_ item: BatchDeletePreviewItemSnapshot) -> String {
        let name = item.currentName ?? item.currentPath ?? "File \(item.fileID)"
        let reason = item.reason.map { " - \($0)" } ?? ""
        return "\(name): \(item.status.rawValue)\(reason)"
    }
}
