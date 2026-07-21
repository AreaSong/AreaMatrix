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
        clearDiagnosticsState()
        if fileID == nil {
            statusBanner = nil
            clearDetail()
        }

        do {
            let loadedFiles = try await fileLister.listFiles(repoPath: repoPath, filter: filter)
            guard generation == loadGeneration else { return }
            files = loadedFiles
            nextFilePageOffset = Int64(loadedFiles.count)
            hasMore = loadedFiles.count == Int(Self.fileListPageSize)
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
        guard !searchState.isActive, hasMore, !isLoading, !isLoadingMore else { return }
        let generation = loadGeneration
        let filter = currentCategoryFilter(offset: nextFilePageOffset)

        isLoadingMore = true
        loadMoreErrorMapping = nil
        do {
            let loadedFiles = try await fileLister.listFiles(repoPath: repoPath, filter: filter)
            guard generation == loadGeneration else { return }
            guard !searchState.isActive else {
                isLoadingMore = false
                return
            }
            files = mergedUniqueFiles(appending: loadedFiles)
            nextFilePageOffset += Int64(loadedFiles.count)
            hasMore = loadedFiles.count == Int(Self.fileListPageSize)
            isLoadingMore = false
        } catch {
            guard generation == loadGeneration else { return }
            guard !searchState.isActive else {
                isLoadingMore = false
                return
            }
            let mappedError = await mapCoreError(error)
            guard generation == loadGeneration else { return }
            guard !searchState.isActive else {
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
}

private extension MainFileListModel {
    func currentCategoryFilter(offset: Int64) -> FileFilterSnapshot {
        var filter = FileFilterSnapshot.currentCategory(currentCategory)
        filter.limit = Self.fileListPageSize
        filter.offset = offset
        return filter
    }

    func resetFilePagination() {
        hasMore = false
        isLoadingMore = false
        loadMoreErrorMapping = nil
        nextFilePageOffset = 0
    }

    func mergedUniqueFiles(appending loadedFiles: [FileEntrySnapshot]) -> [FileEntrySnapshot] {
        var mergedFiles: [FileEntrySnapshot] = []
        var indexByID: [Int64: Int] = [:]

        for file in files + loadedFiles {
            if let index = indexByID[file.id] {
                mergedFiles[index] = file
            } else {
                indexByID[file.id] = mergedFiles.count
                mergedFiles.append(file)
            }
        }
        return mergedFiles
    }
}
