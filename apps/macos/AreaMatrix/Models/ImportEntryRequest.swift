import Foundation

enum ImportEntrySource: Equatable, Sendable {
    case filePicker
    case dropZone
    case dockOpenFile
}

enum ImportEntryDestination: Equatable, Sendable {
    case autoClassify
    case category(String)
    case repositoryRoot
}

enum ImportEntryKind: Equatable, Sendable {
    case singleFile
    case multipleItems(Int)
    case folder
}

struct ImportEntryRequest: Equatable, Sendable, Identifiable {
    let id: UUID
    let repoPath: String
    let source: ImportEntrySource
    let destination: ImportEntryDestination
    let urls: [URL]
    let kind: ImportEntryKind
    let availableCategories: [String]
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
        self.allowReplaceDuringImport = allowReplaceDuringImport
        self.isTrashAvailable = isTrashAvailable
    }

    var sheetTitle: String {
        switch kind {
        case .folder:
            return "Import folder"
        case .singleFile:
            return "导入 1 个文件"
        case .multipleItems(let count):
            return "Import \(count) items"
        }
    }

    var destinationLabel: String {
        switch destination {
        case .autoClassify:
            return "Auto classify"
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return "Repo root"
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
            return "Drop folder to import recursively"
        case .singleFile:
            return "Drop files to import"
        case .multipleItems(let count):
            return "Drop \(count) files to import"
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
