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
            return "File renamed. The same file remains selected."
        case .removedSelectedFile:
            return "Selected file is missing or was removed outside AreaMatrix."
        case .relinkedMissingFile:
            return "Missing file relinked. AreaMatrix updated metadata without moving or modifying the selected file."
        case .unsavedNoteDraftPreserved:
            return "无法保存笔记。草稿已保留，返回该文件的 Note tab 后可继续重试。"
        case .movedFileToTrash:
            return "Moved to Trash. Metadata retained for traceability."
        case .removedFileFromIndex:
            return "Removed from AreaMatrix index. Original file was not deleted."
        case let .batchDeleted(count):
            return "Processed \(count) selected items. List and undo action log are refreshed."
        case let .changedCategory(_, category):
            return "Category changed to \(category). Tree, list, detail, and change log are refreshed."
        case let .correctedClassification(_, category, ruleConfirmationRequired):
            if ruleConfirmationRequired {
                return """
                Classification corrected to \(category). Current file and change log are updated; \
                rule still needs confirmation.
                """
            }
            return "Classification corrected to \(category). Current file and change log are updated."
        case let .savedClassifierRule(category):
            return """
            Classification rule saved for \(category). Future classification uses the updated classifier config.
            """
        case let .changedBatchCategory(count, category):
            return "Changed \(count) files to \(category). List and undo action log are refreshed."
        case let .changedCategoryTreeRefreshFailed(_, category):
            return """
            Category changed to \(category). List, detail, and change log are refreshed. Retry to refresh Tree counts.
            """
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
