import Foundation

enum ImportEntrySource: Equatable {
    case filePicker
    case dropZone
    case dockOpenFile
}

enum ImportEntryDestination: Equatable {
    case autoClassify
    case category(String)
    case repositoryRoot
}

enum ImportEntryKind: Equatable {
    case singleFile
    case multipleItems(Int)
    case folder
}

struct ImportEntryRequest: Equatable, Identifiable {
    let id: UUID
    let repoPath: String
    let source: ImportEntrySource
    let destination: ImportEntryDestination
    let urls: [URL]
    let kind: ImportEntryKind
    let availableCategories: [String]
    let defaultStorageMode: ImportSingleFileStorageMode
    let allowReplaceDuringImport: Bool
    let isTrashAvailable: Bool

    init(
        id: UUID = UUID(),
        repoPath: String,
        source: ImportEntrySource,
        destination: ImportEntryDestination,
        urls: [URL],
        kind: ImportEntryKind,
        availableCategories: [String] = [],
        defaultStorageMode: ImportSingleFileStorageMode = .copy,
        allowReplaceDuringImport: Bool = false,
        isTrashAvailable: Bool = true
    ) {
        self.id = id
        self.repoPath = repoPath
        self.source = source
        self.destination = destination
        self.urls = urls
        self.kind = kind
        self.availableCategories = availableCategories
        self.defaultStorageMode = defaultStorageMode
        self.allowReplaceDuringImport = allowReplaceDuringImport
        self.isTrashAvailable = isTrashAvailable
    }

    var sheetTitle: String {
        switch kind {
        case .folder:
            "Import folder"
        case .singleFile:
            "导入 1 个文件"
        case let .multipleItems(count):
            "导入 \(count) 个文件"
        }
    }

    var destinationLabel: String {
        switch destination {
        case .autoClassify:
            "Auto classify"
        case let .category(slug):
            slug
        case .repositoryRoot:
            "Repo root"
        }
    }
}

extension ImportEntryKind {
    static func resolved(for urls: [URL]) -> ImportEntryKind {
        if urls.contains(where: isDirectory) {
            return .folder
        }

        if urls.count == 1 {
            return .singleFile
        }

        return .multipleItems(urls.count)
    }

    var dropHoverTitle: String {
        switch self {
        case .folder:
            "Drop folder to import recursively"
        case .singleFile:
            "Drop files to import"
        case let .multipleItems(count):
            "Drop \(count) files to import"
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
