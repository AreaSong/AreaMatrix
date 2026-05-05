import Combine
import Foundation

@MainActor
final class MainFileListModel: ObservableObject {
    @Published private(set) var files: [FileEntrySnapshot]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMapping: CoreErrorMappingSnapshot?
    @Published private(set) var selectedFileID: Int64?
    @Published private(set) var selectedFileDetail: FileEntrySnapshot?
    @Published private(set) var isDetailLoading = false
    @Published private(set) var detailErrorMapping: CoreErrorMappingSnapshot?

    private let repoPath: String
    private let fileLister: any CoreFileListing
    private let fileDetailer: any CoreFileDetailing
    private let errorMapper: any CoreErrorMapping
    private var currentCategory: String?
    private var loadGeneration = 0
    private var detailGeneration = 0

    init(
        opening: RepositoryOpeningResult,
        fileLister: any CoreFileListing,
        fileDetailer: any CoreFileDetailing,
        errorMapper: any CoreErrorMapping
    ) {
        repoPath = opening.config.repoPath
        files = opening.currentCategoryFiles
        errorMapping = opening.currentCategoryListError
        self.fileLister = fileLister
        self.fileDetailer = fileDetailer
        self.errorMapper = errorMapper
    }

    func loadCurrentCategory(_ category: String?) async {
        currentCategory = category
        await reloadCurrentCategory()
    }

    func retryCurrentCategory() async {
        await reloadCurrentCategory()
    }

    func selectFile(id: Int64?) async {
        guard let id else {
            clearDetail()
            return
        }

        selectedFileID = id
        selectedFileDetail = nil
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: id)
    }

    func retrySelectedFileDetail() async {
        guard let selectedFileID else { return }

        selectedFileDetail = nil
        detailErrorMapping = nil
        isDetailLoading = true
        await loadDetail(id: selectedFileID)
    }

    private func reloadCurrentCategory() async {
        loadGeneration += 1
        let generation = loadGeneration
        let filter = FileFilterSnapshot.currentCategory(currentCategory)

        isLoading = true
        errorMapping = nil
        clearDetail()

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

    private func loadDetail(id: Int64) async {
        detailGeneration += 1
        let generation = detailGeneration

        do {
            let loadedFile = try await fileDetailer.getFile(repoPath: repoPath, fileID: id)
            guard generation == detailGeneration else { return }
            selectedFileID = loadedFile.id
            selectedFileDetail = loadedFile
            detailErrorMapping = nil
            isDetailLoading = false
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == detailGeneration else { return }
            selectedFileDetail = nil
            detailErrorMapping = mappedError
            isDetailLoading = false
        }
    }

    private func clearDetail() {
        detailGeneration += 1
        selectedFileID = nil
        selectedFileDetail = nil
        detailErrorMapping = nil
        isDetailLoading = false
    }

    private func mapListError(_ error: Error) async -> CoreErrorMappingSnapshot {
        await mapCoreError(error)
    }

    private func mapCoreError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}
