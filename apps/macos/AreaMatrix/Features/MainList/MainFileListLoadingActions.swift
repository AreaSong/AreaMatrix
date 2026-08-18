import AreaMatrixFeatureLibrary
import Foundation

extension MainFileListModel {
    func loadCurrentCategory(_ category: String?, focusingOn fileID: Int64? = nil) async {
        currentCategory = category
        await reloadCurrentCategory(focusingOn: fileID)
    }

    func retryCurrentCategory() async {
        await reloadCurrentCategory()
    }

    func reloadCurrentCategory(focusingOn fileID: Int64? = nil) async {
        loadGeneration += 1
        let generation = loadGeneration
        let filter = currentCategoryFilter(offset: 0)

        isLoading = true
        resetFilePagination()
        errorMapping = nil
        currentListDiagnostics.clear()
        if fileID == nil {
            statusBanner = nil
            clearDetail()
        }

        do {
            let loadedFiles = try await fileLister.listFiles(repoPath: repoPath, filter: filter)
            guard generation == loadGeneration else { return }
            files = loadedFiles
            applyReplacedPage(itemCount: loadedFiles.count, requestedLimit: MainListPagination.defaultPageSize)
            errorMapping = nil
            isLoading = false
            focusLoadedFile(fileID: fileID)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == loadGeneration else { return }
            files = []
            errorMapping = mappedError
            statusBanner = nil
            isLoading = false
        }
    }

    func loadMoreCurrentCategory() async {
        guard !searchModel.searchState.isActive, hasMore, !isLoading, !isLoadingMore else { return }
        let generation = loadGeneration
        let filter = currentCategoryFilter(offset: nextFilePageOffset)

        isLoadingMore = true
        loadMoreErrorMapping = nil
        do {
            let loadedFiles = try await fileLister.listFiles(repoPath: repoPath, filter: filter)
            guard generation == loadGeneration else { return }
            guard !searchModel.searchState.isActive else {
                isLoadingMore = false
                return
            }
            files = MainListPagination.mergingUnique(
                existing: files,
                appending: loadedFiles,
                id: \FileEntrySnapshot.id
            )
            applyAppendedPage(itemCount: loadedFiles.count)
            isLoadingMore = false
        } catch {
            guard generation == loadGeneration else { return }
            guard !searchModel.searchState.isActive else {
                isLoadingMore = false
                return
            }
            let mappedError = await mapCoreError(error)
            guard generation == loadGeneration else { return }
            guard !searchModel.searchState.isActive else {
                isLoadingMore = false
                return
            }
            loadMoreErrorMapping = mappedError
            isLoadingMore = false
        }
    }

    private func focusLoadedFile(fileID: Int64?) {
        guard let fileID, let file = files.first(where: { $0.id == fileID }) else { return }
        selection = .single(file.id)
        selectedFileDetail = file
        selectedFileNoteWriteBlock = noteWriteBlock(for: file)
        detailErrorMapping = nil
        isDetailLoading = false
    }

    private func currentCategoryFilter(offset: Int64) -> FileFilterSnapshot {
        var filter = FileFilterSnapshot.currentCategory(currentCategory)
        filter.limit = MainListPagination.defaultPageSize
        filter.offset = offset
        return filter
    }

    func resetFilePagination() {
        var pagination = MainListPagination(initialCount: 0)
        pagination.reset()
        hasMore = false
        isLoadingMore = false
        loadMoreErrorMapping = nil
        nextFilePageOffset = pagination.nextOffset
    }

    private func applyReplacedPage(itemCount: Int, requestedLimit: Int64) {
        var pagination = MainListPagination(initialCount: 0)
        pagination.replace(itemCount: itemCount, requestedLimit: requestedLimit)
        nextFilePageOffset = pagination.nextOffset
        hasMore = pagination.hasMore
    }

    private func applyAppendedPage(itemCount: Int) {
        var pagination = MainListPagination(initialCount: Int(nextFilePageOffset))
        pagination.append(itemCount: itemCount)
        nextFilePageOffset = pagination.nextOffset
        hasMore = pagination.hasMore
    }
}
