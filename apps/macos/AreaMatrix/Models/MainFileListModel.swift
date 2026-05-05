import Combine
import Foundation

@MainActor
final class MainFileListModel: ObservableObject {
    @Published private(set) var files: [FileEntrySnapshot]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMapping: CoreErrorMappingSnapshot?

    private let repoPath: String
    private let fileLister: any CoreFileListing
    private let errorMapper: any CoreErrorMapping
    private var currentCategory: String?
    private var loadGeneration = 0

    init(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        errorMapper: any CoreErrorMapping
    ) {
        repoPath = opening.config.repoPath
        files = opening.currentCategoryFiles
        errorMapping = opening.currentCategoryListError
        self.fileLister = fileLister
        self.errorMapper = errorMapper
    }

    func loadCurrentCategory(_ category: String?) async {
        currentCategory = category
        await reloadCurrentCategory()
    }

    func retryCurrentCategory() async {
        await reloadCurrentCategory()
    }

    private func reloadCurrentCategory() async {
        loadGeneration += 1
        let generation = loadGeneration
        let filter = FileFilterSnapshot.currentCategory(currentCategory)

        isLoading = true
        errorMapping = nil

        do {
            let loadedFiles = try await fileLister.listFiles(repoPath: repoPath, filter: filter)
            guard generation == loadGeneration else { return }
            files = loadedFiles
            errorMapping = nil
            isLoading = false
        } catch {
            let mappedError = await mapListError(error)
            guard generation == loadGeneration else { return }
            files = []
            errorMapping = mappedError
            isLoading = false
        }
    }

    private func mapListError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}
