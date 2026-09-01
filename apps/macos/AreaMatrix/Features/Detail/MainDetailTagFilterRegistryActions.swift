import Foundation

extension DetailTagModel {
    func loadTagFilterRegistry(activeFileID: Int64?) async {
        guard let activeFileID else {
            clearTagFilterRegistry()
            return
        }
        await loadTagFilterRegistry(fileID: activeFileID)
    }

    func retryTagFilterRegistry() async {
        switch filterRegistryState {
        case let .failed(fileID, _, _), let .loaded(fileID, _), let .loading(fileID, _):
            await loadTagFilterRegistry(fileID: fileID)
        case .idle:
            return
        }
    }

    func clearTagFilterRegistry() {
        filterRegistryGeneration += 1
        filterRegistryState = .idle
    }

    private func loadTagFilterRegistry(fileID: Int64) async {
        filterRegistryGeneration += 1
        let generation = filterRegistryGeneration
        let previous = filterRegistryState.tagSet
        filterRegistryState = .loading(fileID: fileID, previous: previous)

        do {
            let tagSet = try await tagStore.listTags(repoPath: repoPath, fileID: fileID)
            guard generation == filterRegistryGeneration else { return }
            filterRegistryState = .loaded(fileID: fileID, tagSet)
        } catch {
            let mappedError = await mapCoreError(error)
            guard generation == filterRegistryGeneration else { return }
            filterRegistryState = .failed(fileID: fileID, mappedError, previous: previous)
        }
    }
}
