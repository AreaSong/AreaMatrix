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
        let filter = FileFilterSnapshot.currentCategory(currentCategory)

        isLoading = true
        errorMapping = nil
        diagnosticsState = .idle
        if fileID == nil {
            statusBanner = nil
            clearDetail()
        }

        do {
            let loadedFiles = try await fileLister.listFiles(repoPath: repoPath, filter: filter)
            guard generation == loadGeneration else { return }
            files = loadedFiles
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

    private func focusLoadedFile(fileID: Int64?) {
        guard let fileID, let file = files.first(where: { $0.id == fileID }) else { return }
        selection = .single(file.id)
        selectedFileDetail = file
        selectedFileNoteWriteBlock = noteWriteBlock(for: file)
        detailErrorMapping = nil
        isDetailLoading = false
    }
}
