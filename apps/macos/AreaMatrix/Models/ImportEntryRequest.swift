import Foundation

enum ImportEntrySource: Equatable, Sendable {
    case filePicker
    case dropZone
}

enum ImportEntryDestination: Equatable, Sendable {
    case autoClassify
    case category(String)
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

    init(
        id: UUID = UUID(),
        repoPath: String,
        source: ImportEntrySource,
        destination: ImportEntryDestination,
        urls: [URL],
        kind: ImportEntryKind
    ) {
        self.id = id
        self.repoPath = repoPath
        self.source = source
        self.destination = destination
        self.urls = urls
        self.kind = kind
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
        }
    }

}
