import Foundation

struct MainFileCategoryMovePreviewRequest: Equatable {
    var fileID: Int64
    var targetCategory: String
}

enum MainFileCategoryMoveFailureOperation: Equatable {
    case preview
    case move
}

enum MainFileCategoryMoveState: Equatable {
    case idle
    case checking(MainFileCategoryMovePreviewRequest)
    case ready(MainFileCategoryMovePreviewRequest, MoveToCategoryPreviewSnapshot)
    case moving(MainFileCategoryMovePreviewRequest, preview: MoveToCategoryPreviewSnapshot?)
    case failed(
        MainFileCategoryMovePreviewRequest,
        operation: MainFileCategoryMoveFailureOperation,
        CoreErrorMappingSnapshot
    )

    func isChecking(_ request: MainFileCategoryMovePreviewRequest) -> Bool {
        guard case let .checking(currentRequest) = self else { return false }
        return currentRequest == request
    }

    func isChecking(fileID: Int64, targetCategory: String) -> Bool {
        isChecking(MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory))
    }

    func isMoving(fileID: Int64) -> Bool {
        guard case let .moving(request, _) = self else { return false }
        return request.fileID == fileID
    }

    func preview(for request: MainFileCategoryMovePreviewRequest) -> MoveToCategoryPreviewSnapshot? {
        switch self {
        case let .ready(currentRequest, preview) where currentRequest == request:
            preview
        case let .moving(currentRequest, preview) where currentRequest == request:
            preview
        default:
            nil
        }
    }

    func failure(for fileID: Int64, targetCategory: String) -> CoreErrorMappingSnapshot? {
        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        guard case let .failed(currentRequest, _, mapping) = self,
              currentRequest == request else { return nil }
        return mapping
    }

    func failureOperation(
        for fileID: Int64,
        targetCategory: String
    ) -> MainFileCategoryMoveFailureOperation? {
        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        guard case let .failed(currentRequest, operation, _) = self,
              currentRequest == request else { return nil }
        return operation
    }

    func unresolvedNameConflict(
        for fileID: Int64,
        targetCategory: String
    ) -> CoreErrorMappingSnapshot? {
        guard failureOperation(for: fileID, targetCategory: targetCategory) == .preview,
              let mapping = failure(for: fileID, targetCategory: targetCategory),
              mapping.kind == .conflict else { return nil }
        return mapping
    }
}
