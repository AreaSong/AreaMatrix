import Foundation

struct BatchCategoryPreviewReportPresentation: Equatable {
    var moveSummaryText: String
    var metadataSummaryText: String
    var skippedSummaryText: String
    var blockedSummaryText: String

    init(report: BatchCategoryPreviewReportSnapshot) {
        moveSummaryText = "\(Self.fileText(report.willMoveCount)) will move"
        metadataSummaryText = "\(Self.fileText(report.metadataOnlyCount)) will update only"
        skippedSummaryText = "\(Self.fileText(report.skippedCount)) cannot move"
        blockedSummaryText = "\(Self.fileText(report.blockedCount)) blocked"
    }

    private static func fileText(_ count: Int64) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }
}

struct BatchCategoryChangeReportPresentation: Equatable {
    var changedSummaryText: String
    var skippedSummaryText: String
    var failedSummaryText: String

    init(report: BatchCategoryChangeReportSnapshot) {
        let changed = report.movedCount + report.metadataOnlyCount
        changedSummaryText = "\(Self.fileText(changed)) changed"
        skippedSummaryText = "\(Self.fileText(report.skippedCount + report.unchangedCount)) skipped or unchanged"
        failedSummaryText = "\(Self.fileText(report.failedCount)) failed"
    }

    private static func fileText(_ count: Int64) -> String {
        count == 1 ? "1 file" : "\(count) files"
    }
}
