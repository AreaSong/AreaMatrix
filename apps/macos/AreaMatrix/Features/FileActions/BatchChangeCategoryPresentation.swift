import Foundation

struct BatchCategoryPreviewReportPresentation: Equatable {
    var moveSummaryText: LocalizedMessage
    var metadataSummaryText: LocalizedMessage
    var skippedSummaryText: LocalizedMessage
    var blockedSummaryText: LocalizedMessage

    init(report: BatchCategoryPreviewReportSnapshot) {
        moveSummaryText = L10n.pluralMessage(
            "file-actions.change-category.preview.will-move",
            count: report.willMoveCount
        )
        metadataSummaryText = L10n.pluralMessage(
            "file-actions.change-category.preview.metadata-only",
            count: report.metadataOnlyCount
        )
        skippedSummaryText = L10n.pluralMessage(
            "file-actions.change-category.preview.cannot-move",
            count: report.skippedCount
        )
        blockedSummaryText = L10n.pluralMessage(
            "file-actions.change-category.preview.blocked",
            count: report.blockedCount
        )
    }
}

struct BatchCategoryChangeReportPresentation: Equatable {
    var changedSummaryText: LocalizedMessage
    var skippedSummaryText: LocalizedMessage
    var failedSummaryText: LocalizedMessage

    init(report: BatchCategoryChangeReportSnapshot) {
        let changed = report.movedCount + report.metadataOnlyCount
        changedSummaryText = L10n.pluralMessage("file-actions.change-category.result.changed", count: changed)
        skippedSummaryText = L10n.pluralMessage(
            "file-actions.change-category.result.skipped-or-unchanged",
            count: report.skippedCount + report.unchangedCount
        )
        failedSummaryText = L10n.pluralMessage(
            "file-actions.change-category.result.failed",
            count: report.failedCount
        )
    }
}
