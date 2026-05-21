import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct FileDropAdapter {
    let onDrop: ([URL]) -> Void

    func handle(_ providers: [NSItemProvider]) -> Bool {
        let fileURLProviders = Self.fileURLProviders(from: providers)
        guard !fileURLProviders.isEmpty else { return false }

        Self.loadFileURLs(from: fileURLProviders) { urls in
            onDrop(urls)
        }
        return true
    }

    static func fileURLProviders(from providers: [NSItemProvider]) -> [NSItemProvider] {
        providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
    }

    static func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = Self.fileURL(from: item) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(urls)
        }
    }

    static func fileURL(from item: NSSecureCoding?) -> URL? {
        switch item {
        case let url as URL:
            return url.isFileURL ? url : nil
        case let data as Data:
            guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                return nil
            }
            return url
        case let string as String:
            let url = URL(fileURLWithPath: string)
            return url.path.isEmpty ? nil : url
        default:
            return nil
        }
    }
}

extension MainRepositoryContentView {
    var dropOverlay: some View {
        Group {
            if let presentation = dropPreviewModel.presentation {
                DropZoneOverlay(presentation: presentation)
                    .padding(24)
            }
        }
    }

    @ViewBuilder
    func contextMenu(for selection: Set<Int64>) -> some View {
        let selectedFiles = files(for: selection)
        if selectedFiles.count == 1, let file = selectedFiles.first {
            singleFileContextMenu(for: file)
        } else {
            multiFileContextMenu(for: selection, selectedFiles: selectedFiles)
        }
    }

    @ViewBuilder
    private func singleFileContextMenu(for file: FileEntrySnapshot) -> some View {
        Button("Show in Finder") {
            onShowInFinder(file.path)
        }
        Button("Rename...") {
            fileListModel.beginRename(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Button("Change Category...") {
            fileListModel.beginChangeCategory(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Button("Delete...", role: .destructive) {
            fileListModel.beginDelete(fileID: file.id)
        }
        .disabled(fileListModel.writeActionDisabledReason(fileID: file.id) != nil)
        Divider()
        Button("Copy Path") {
            onCopyPath(file.path)
        }
    }

    @ViewBuilder
    private func multiFileContextMenu(for selection: Set<Int64>, selectedFiles: [FileEntrySnapshot]) -> some View {
        if selectedFiles.count > 1 {
            Button("Add tags...") {
                openBatchAddTagsRoute(selection, source: .listContextMenu)
            }
            Button("Change category...") {
                openBatchChangeCategoryRoute(selection, source: .listContextMenu)
            }
        }
        Button("Copy Paths") {
            onCopyPaths(selectedFiles.map(\.path))
        }
        .disabled(selectedFiles.isEmpty)
    }

    func files(for selection: Set<Int64>) -> [FileEntrySnapshot] {
        visibleFiles.filter { selection.contains($0.id) }
    }
}
