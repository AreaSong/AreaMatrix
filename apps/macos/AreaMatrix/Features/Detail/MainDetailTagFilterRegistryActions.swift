import Foundation

extension MainFileListModel {
    func loadTagFilterRegistry(activeFileID: Int64?) async {
        guard let activeFileID else {
            clearTagFilterRegistry()
            return
        }
        await loadTagFilterRegistry(fileID: activeFileID)
    }

    func retryTagFilterRegistry() async {
        switch tagFilterRegistryState {
        case let .failed(fileID, _, _), let .loaded(fileID, _), let .loading(fileID, _):
            await loadTagFilterRegistry(fileID: fileID)
        case .idle:
            return
        }
    }

    func clearTagFilterRegistry() {
        tagFilterRegistryGeneration += 1
        tagFilterRegistryState = .idle
    }

    private func loadTagFilterRegistry(fileID: Int64) async {
        tagFilterRegistryGeneration += 1
        let generation = tagFilterRegistryGeneration
        let previous = tagFilterRegistryState.tagSet
        tagFilterRegistryState = .loading(fileID: fileID, previous: previous)

        do {
            let tagSet = try await tagStore.listTags(repoPath: repoPath, fileID: fileID)
            guard generation == tagFilterRegistryGeneration else { return }
            tagFilterRegistryState = .loaded(fileID: fileID, tagSet)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == tagFilterRegistryGeneration else { return }
            tagFilterRegistryState = .failed(fileID: fileID, mappedError, previous: previous)
        }
    }
}
