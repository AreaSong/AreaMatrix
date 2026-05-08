import Foundation

struct MainFileCategoryMovePreviewRequest: Equatable, Sendable {
    var fileID: Int64
    var targetCategory: String
}

enum MainFileCategoryMoveFailureOperation: Equatable, Sendable {
    case preview
    case move
}

enum MainFileCategoryMoveState: Equatable, Sendable {
    case idle
    case checking(MainFileCategoryMovePreviewRequest)
    case ready(MainFileCategoryMovePreviewRequest, MoveToCategoryPreviewSnapshot)
    case moving(MainFileCategoryMovePreviewRequest, preview: MoveToCategoryPreviewSnapshot?)
    case failed(MainFileCategoryMovePreviewRequest, operation: MainFileCategoryMoveFailureOperation, CoreErrorMappingSnapshot)

    func isChecking(_ request: MainFileCategoryMovePreviewRequest) -> Bool {
        guard case .checking(let currentRequest) = self else { return false }
        return currentRequest == request
    }

    func isChecking(fileID: Int64, targetCategory: String) -> Bool {
        isChecking(MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory))
    }

    func isMoving(fileID: Int64) -> Bool {
        guard case .moving(let request, _) = self else { return false }
        return request.fileID == fileID
    }

    func preview(for request: MainFileCategoryMovePreviewRequest) -> MoveToCategoryPreviewSnapshot? {
        switch self {
        case .ready(let currentRequest, let preview) where currentRequest == request:
            return preview
        case .moving(let currentRequest, let preview) where currentRequest == request:
            return preview
        default:
            return nil
        }
    }

    func failure(for fileID: Int64, targetCategory: String) -> CoreErrorMappingSnapshot? {
        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        guard case .failed(let currentRequest, _, let mapping) = self,
              currentRequest == request else { return nil }
        return mapping
    }

    func failureOperation(
        for fileID: Int64,
        targetCategory: String
    ) -> MainFileCategoryMoveFailureOperation? {
        let request = MainFileCategoryMovePreviewRequest(fileID: fileID, targetCategory: targetCategory)
        guard case .failed(let currentRequest, let operation, _) = self,
              currentRequest == request else { return nil }
        return operation
    }
}
