import Foundation

struct BatchCategoryPreviewReportPresentation: Equatable {
    var moveSummaryText: String
    var metadataSummaryText: String
    var skippedSummaryText: String
    var blockedSummaryText: String

    init(report: BatchCategoryPreviewReportSnapshot) {
        moveSummaryText = L10n.plural(
            "file-actions.change-category.preview.will-move",
            count: Int(report.willMoveCount)
        )
        metadataSummaryText = L10n.plural(
            "file-actions.change-category.preview.metadata-only",
            count: Int(report.metadataOnlyCount)
        )
        skippedSummaryText = L10n.plural(
            "file-actions.change-category.preview.cannot-move",
            count: Int(report.skippedCount)
        )
        blockedSummaryText = L10n.plural(
            "file-actions.change-category.preview.blocked",
            count: Int(report.blockedCount)
        )
    }
}

struct BatchCategoryChangeReportPresentation: Equatable {
    var changedSummaryText: String
    var skippedSummaryText: String
    var failedSummaryText: String

    init(report: BatchCategoryChangeReportSnapshot) {
        let changed = report.movedCount + report.metadataOnlyCount
        changedSummaryText = L10n.plural("file-actions.change-category.result.changed", count: Int(changed))
        skippedSummaryText = L10n.plural(
            "file-actions.change-category.result.skipped-or-unchanged",
            count: Int(report.skippedCount + report.unchangedCount)
        )
        failedSummaryText = L10n.plural(
            "file-actions.change-category.result.failed",
            count: Int(report.failedCount)
        )
    }
}
