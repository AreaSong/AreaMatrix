import Foundation

enum MainListStatusBanner: Equatable {
    case renamedPreservedSelection(fileID: Int64)
    case removedSelectedFile(fileID: Int64)
    case relinkedMissingFile(fileID: Int64)
    case unsavedNoteDraftPreserved(fileID: Int64)
    case movedFileToTrash(fileID: Int64)
    case removedFileFromIndex(fileID: Int64)
    case batchDeleted(count: Int64)
    case changedCategory(fileID: Int64, category: String)
    case correctedClassification(fileID: Int64, category: String, ruleConfirmationRequired: Bool)
    case savedClassifierRule(category: String)
    case changedBatchCategory(count: Int64, category: String)
    case changedCategoryTreeRefreshFailed(fileID: Int64, category: String)
    case resolvedICloudConflict(fileID: Int64, strategy: ICloudConflictResolutionStrategy)

    var message: String {
        switch self {
        case .renamedPreservedSelection:
            return L10n.string("File renamed. The same file remains selected.")
        case .removedSelectedFile:
            return L10n.string("Selected file is missing or was removed outside AreaMatrix.")
        case .relinkedMissingFile:
            return L10n
                .string(
                    "Missing file relinked. AreaMatrix updated metadata without moving or modifying the selected file."
                )
        case .unsavedNoteDraftPreserved:
            return L10n.string("无法保存笔记。草稿已保留，返回该文件的 Note tab 后可继续重试。")
        case .movedFileToTrash:
            return L10n.string("Moved to Trash. Metadata retained for traceability.")
        case .removedFileFromIndex:
            return L10n.string("Removed from AreaMatrix index. Original file was not deleted.")
        case let .batchDeleted(count):
            return L10n.format("mainList.status.batchDeleted", count)
        case let .changedCategory(_, category):
            return L10n.format("mainList.status.categoryChanged", category)
        case let .correctedClassification(_, category, ruleConfirmationRequired):
            if ruleConfirmationRequired {
                return L10n.format("mainList.status.classificationCorrectedRuleConfirmation", category)
            }
            return L10n.format("mainList.status.classificationCorrected", category)
        case let .savedClassifierRule(category):
            return L10n.format("mainList.status.classificationRuleSaved", category)
        case let .changedBatchCategory(count, category):
            return L10n.format("mainList.status.batchCategoryChanged", count, category)
        case let .changedCategoryTreeRefreshFailed(_, category):
            return L10n.format("mainList.status.categoryChangedTreeRefreshFailed", category)
        case let .resolvedICloudConflict(_, strategy):
            return strategy.successMessage
        }
    }

    var systemImage: String {
        switch self {
        case .renamedPreservedSelection:
            "arrow.triangle.2.circlepath"
        case .removedSelectedFile, .unsavedNoteDraftPreserved, .changedCategoryTreeRefreshFailed:
            "exclamationmark.triangle"
        case .relinkedMissingFile, .movedFileToTrash, .removedFileFromIndex, .batchDeleted, .changedCategory,
             .correctedClassification,
             .savedClassifierRule, .changedBatchCategory, .resolvedICloudConflict:
            "checkmark.circle"
        }
    }
}
