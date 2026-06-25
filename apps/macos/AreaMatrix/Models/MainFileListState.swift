import Foundation

enum DetailPaneTab: String, CaseIterable, Identifiable {
    case meta
    case summary
    case log
    case note

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .meta:
            "Meta"
        case .summary:
            "Summary"
        case .log:
            "Log"
        case .note:
            "Note"
        }
    }
}

enum MainFileActionDestination: Equatable {
    case rename(fileID: Int64)
    case aiClassificationSuggestion(fileID: Int64, returnContext: AIClassificationSuggestionReturnContext? = nil)
    case changeCategory(
        fileID: Int64,
        initialTargetCategory: String? = nil,
        mode: MainFileCategoryMoveMode = .moveToCategory,
        ruleRoute: ClassifierCorrectionRuleRoute? = nil
    )
    case delete(fileID: Int64)
    case iCloudConflict(fileID: Int64)

    var pageID: String {
        switch self {
        case .rename:
            "rename-file"
        case .aiClassificationSuggestion:
            "ai-category-suggestion"
        case let .changeCategory(_, _, mode, ruleRoute):
            ruleRoute?.pageID ?? (mode == .classifierCorrection ? "classifier-correction" : "change-category")
        case .delete:
            "delete-file"
        case .iCloudConflict:
            "icloud-conflict-minimal"
        }
    }

    var pageTitle: String {
        switch self {
        case .rename:
            "Rename File"
        case .aiClassificationSuggestion:
            "AI Category Suggestion"
        case let .changeCategory(_, _, mode, ruleRoute):
            switch ruleRoute {
            case .saveRule:
                "Save Classifier Rule"
            case .impactPreview:
                "Preview Classifier Impact"
            case nil:
                mode == .classifierCorrection ? "Correct Classification" : "Change Category"
            }
        case .delete:
            "Move File to Trash?"
        case .iCloudConflict:
            "Resolve iCloud Conflict"
        }
    }

    var fileID: Int64 {
        switch self {
        case let .rename(fileID), let .aiClassificationSuggestion(fileID, _),
             let .changeCategory(fileID, _, _, _), let .delete(fileID), let .iCloudConflict(fileID):
            fileID
        }
    }

    var initialChangeCategoryTarget: String? {
        guard case let .changeCategory(_, targetCategory, _, _) = self else { return nil }
        return targetCategory
    }

    var changeCategoryMode: MainFileCategoryMoveMode {
        guard case let .changeCategory(_, _, mode, _) = self else { return .moveToCategory }
        return mode
    }

    var classifierRuleRoute: ClassifierCorrectionRuleRoute? {
        guard case let .changeCategory(_, _, _, ruleRoute) = self else { return nil }
        return ruleRoute
    }

    var aiClassificationReturnContext: AIClassificationSuggestionReturnContext? {
        guard case let .aiClassificationSuggestion(_, context) = self else { return nil }
        return context
    }

    func isChangeCategory(fileID expectedFileID: Int64) -> Bool {
        guard case let .changeCategory(fileID, _, _, _) = self else { return false }
        return fileID == expectedFileID
    }

    func isAIClassificationSuggestion(fileID expectedFileID: Int64) -> Bool {
        guard case let .aiClassificationSuggestion(fileID, _) = self else { return false }
        return fileID == expectedFileID
    }

    func supportsCategoryPreview(fileID expectedFileID: Int64) -> Bool {
        isChangeCategory(fileID: expectedFileID) || isAIClassificationSuggestion(fileID: expectedFileID)
    }
}

extension MainFileActionDestination: Identifiable {
    var id: String {
        "\(pageID)-\(fileID)"
    }
}

enum MainFileDeleteOperation: String, Equatable {
    case moveToTrash
    case removeFromIndex

    static func recommended(for file: FileEntrySnapshot) -> MainFileDeleteOperation {
        if file.storageMode == "Indexed" ||
            file.origin == "Adopted" ||
            file.origin == "External" ||
            file.availability == .missing {
            return .removeFromIndex
        }
        return .moveToTrash
    }

    var title: String {
        switch self {
        case .moveToTrash:
            "Move File to Trash?"
        case .removeFromIndex:
            "Remove from Index?"
        }
    }

    var message: String {
        switch self {
        case .moveToTrash:
            "AreaMatrix will move this file to the system Trash and keep a change-log record."
        case .removeFromIndex:
            "This removes the AreaMatrix index entry. It does not delete the original file."
        }
    }

    var confirmationText: String {
        switch self {
        case .moveToTrash:
            "我理解该文件会被移到系统废纸篓"
        case .removeFromIndex:
            "我理解该条目会从 AreaMatrix 索引中移除"
        }
    }

    var actionTitle: String {
        switch self {
        case .moveToTrash:
            "Move to Trash"
        case .removeFromIndex:
            "Remove from Index"
        }
    }

    var runningTitle: String {
        switch self {
        case .moveToTrash:
            "Moving to Trash..."
        case .removeFromIndex:
            "Removing..."
        }
    }

    var failureTitle: String {
        switch self {
        case .moveToTrash:
            "Move to Trash failed"
        case .removeFromIndex:
            "Remove from Index failed"
        }
    }

    func successBanner(fileID: Int64) -> MainListStatusBanner {
        switch self {
        case .moveToTrash:
            .movedFileToTrash(fileID: fileID)
        case .removeFromIndex:
            .removedFileFromIndex(fileID: fileID)
        }
    }
}

enum MainFileDeleteState: Equatable {
    case idle
    case deleting(fileID: Int64, operation: MainFileDeleteOperation)
    case failed(fileID: Int64, operation: MainFileDeleteOperation, CoreErrorMappingSnapshot)

    var isDeleting: Bool {
        if case .deleting = self { return true }
        return false
    }

    func isDeleting(fileID: Int64) -> Bool {
        guard case let .deleting(deletingFileID, _) = self else { return false }
        return deletingFileID == fileID
    }

    func failure(for fileID: Int64) -> CoreErrorMappingSnapshot? {
        guard case let .failed(failedFileID, _, mapping) = self,
              failedFileID == fileID else { return nil }
        return mapping
    }

    func primaryActionTitle(fileID: Int64, operation: MainFileDeleteOperation) -> String {
        if isDeleting(fileID: fileID) { return operation.runningTitle }
        if failure(for: fileID) != nil { return "Retry" }
        return operation.actionTitle
    }
}

enum MainDetailTabRequest: Equatable {
    case automatic(DetailPaneTab)
}

enum MainFileWriteActionDisabledReason: String, Equatable {
    case repoReadOnly = "Repository is read-only"
    case listLoading = "Current list is loading"
    case importLocked = "This file is locked by an import"
}

enum MainFileRenameState: Equatable {
    case idle
    case renaming(fileID: Int64)
    case returningToChangeCategory(fileID: Int64, targetCategory: String)
    case renamingFromChangeCategory(fileID: Int64, targetCategory: String)
    case failed(fileID: Int64, CoreErrorMappingSnapshot)
    case failedFromChangeCategory(fileID: Int64, targetCategory: String, CoreErrorMappingSnapshot)

    var isRenaming: Bool {
        switch self {
        case .renaming, .renamingFromChangeCategory:
            true
        case .idle, .returningToChangeCategory, .failed, .failedFromChangeCategory:
            false
        }
    }

    func failure(for fileID: Int64) -> CoreErrorMappingSnapshot? {
        switch self {
        case let .failed(failedFileID, mapping) where failedFileID == fileID:
            mapping
        case let .failedFromChangeCategory(failedFileID, _, mapping) where failedFileID == fileID:
            mapping
        default:
            nil
        }
    }

    func changeCategoryReturnTarget(for fileID: Int64) -> String? {
        switch self {
        case let .returningToChangeCategory(returningFileID, targetCategory) where returningFileID == fileID:
            targetCategory
        case let .renamingFromChangeCategory(returningFileID, targetCategory) where returningFileID == fileID:
            targetCategory
        case let .failedFromChangeCategory(returningFileID, targetCategory, _) where returningFileID == fileID:
            targetCategory
        default:
            nil
        }
    }
}

enum MainFileActionCategoryOptions {
    static func availableCategories(
        file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> [String] {
        let categories = categoryRows.compactMap(\.categoryForFileList)
        let current = file.map { [$0.category] } ?? []
        return Array(Set(categories + current)).sorted()
    }

    static func defaultTargetCategory(
        for file: FileEntrySnapshot?,
        categoryRows: [RepositorySidebarRowSnapshot]
    ) -> String {
        let categories = availableCategories(file: nil, categoryRows: categoryRows)
        return categories.first { $0 != file?.category } ?? file?.category ?? ""
    }
}

enum MainListDiagnosticsState: Equatable {
    case idle
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(CoreErrorMappingSnapshot)
}

enum MainDetailLogState: Equatable {
    case notLoaded
    case loading(fileID: Int64)
    case loaded(fileID: Int64, entries: [ChangeLogEntrySnapshot])
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var entries: [ChangeLogEntrySnapshot]? {
        guard case let .loaded(_, entries) = self else { return nil }
        return entries
    }
}

enum MainDetailLogDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy(fileID: Int64)
    case collecting(fileID: Int64)
    case collected(fileID: Int64, DiagnosticsSnapshotSnapshot)
    case failed(fileID: Int64, CoreErrorMappingSnapshot)

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}
