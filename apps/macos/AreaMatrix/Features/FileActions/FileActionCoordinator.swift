import Combine
import Foundation

struct FileActionDeleteOutcome {
    let fileID: Int64
    let operation: MainFileDeleteOperation
}

struct FileActionRenameOutcome {
    let file: FileEntrySnapshot
    let returnTargetCategory: String?
}

struct FileActionCategoryOutcome {
    let file: FileEntrySnapshot
    let mode: MainFileCategoryMoveMode
    let correction: ClassifierCorrectionResultSnapshot?
}

@MainActor
final class FileActionCoordinator: ObservableObject {
    @Published var destination: MainFileActionDestination?
    @Published var renameState = MainFileRenameState.idle
    @Published var deleteState = MainFileDeleteState.idle
    @Published var changeCategoryState = MainFileCategoryMoveState.idle
    @Published var classifierCorrectionContextState = ClassifierCorrectionContextState.idle
    @Published var classifierCorrectionResult: ClassifierCorrectionResultSnapshot?
    @Published var routingState = MainFileActionRoutingState()

    let repoPath: String
    let fileRenamer: any CoreFileRenaming
    let fileDeleter: any CoreFileDeleting
    let fileCategoryMover: any CoreFileCategoryMoving
    let categoryPredictor: any CoreCategoryPredicting
    let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        fileRenamer: any CoreFileRenaming,
        fileDeleter: any CoreFileDeleting,
        fileCategoryMover: any CoreFileCategoryMoving,
        categoryPredictor: any CoreCategoryPredicting,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.fileRenamer = fileRenamer
        self.fileDeleter = fileDeleter
        self.fileCategoryMover = fileCategoryMover
        self.categoryPredictor = categoryPredictor
        self.errorMapper = errorMapper
    }

    func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await errorMapper.mapError(error)
    }

    var pendingActionDestination: MainFileActionDestination? {
        get { destination }
        set { destination = newValue }
    }
}
