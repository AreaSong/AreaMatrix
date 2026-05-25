import Foundation

enum ImportEntrySource: Equatable {
    case filePicker
    case dropZone
    case dockOpenFile
    case importConflictBatch(CommandPaletteLinkedPageRoute?)
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
    let importSessionID: String?
    let importConflictIDs: [String]
    let importConflictIDsBySourcePath: [String: String]

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
        isTrashAvailable: Bool = true,
        importSessionID: String? = nil,
        importConflictIDs: [String] = [],
        importConflictIDsBySourcePath: [String: String] = [:]
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
        self.importSessionID = importSessionID
        self.importConflictIDs = importConflictIDs
        self.importConflictIDsBySourcePath = importConflictIDsBySourcePath
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

    var importConflictBatchRoute: ImportConflictBatchRoute? {
        guard let importSessionID else { return nil }
        let conflictIDs = importConflictIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !conflictIDs.isEmpty else { return nil }
        let sourceRoute: CommandPaletteLinkedPageRoute?
        if case let .importConflictBatch(route) = source {
            sourceRoute = route
        } else {
            sourceRoute = nil
        }
        return ImportConflictBatchRoute(
            importSessionID: importSessionID,
            conflictIDs: conflictIDs,
            source: sourceRoute
        )
    }

    func importConflictID(forSourcePath sourcePath: String) -> String? {
        importConflictIDsBySourcePath[sourcePath] ??
            importConflictIDsBySourcePath[(sourcePath as NSString).abbreviatingWithTildeInPath]
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

enum CommandPaletteLinkedPageRoute: String, Equatable, Identifiable, CaseIterable {
    case classifierImpactPreview = "S2-18"
    case importConflictBatch = "S2-21"
    case redo = "S2-22"
    case tagSuggestions = "S2-23"

    var id: String { rawValue }
    var pageID: String { rawValue }

    var blockedMapping: CoreErrorMappingSnapshot {
        switch self {
        case .classifierImpactPreview:
            CoreErrorMappingSnapshot(
                kind: .validation,
                userMessage: "Classifier impact preview is not available yet.",
                severity: .medium,
                suggestedAction: "Open classifier rules first; S2-18 will provide the real preview flow.",
                recoverability: .userActionRequired,
                rawContext: pageID
            )
        case .importConflictBatch:
            CoreErrorMappingSnapshot(
                kind: .stagingRecoveryRequired,
                userMessage: "There is no active import conflict batch to review.",
                severity: .medium,
                suggestedAction: "Start or resume a batch import with unresolved conflicts.",
                recoverability: .userActionRequired,
                rawContext: pageID
            )
        case .redo:
            CoreErrorMappingSnapshot(
                kind: .conflict,
                userMessage: "Redo latest is handled in Undo History.",
                severity: .medium,
                suggestedAction: "Review Undo History until S2-22 redo is available.",
                recoverability: .refreshRequired,
                rawContext: pageID
            )
        case .tagSuggestions:
            CoreErrorMappingSnapshot(
                kind: .validation,
                userMessage: "Select a file before reviewing tag suggestions.",
                severity: .medium,
                suggestedAction: "Open a file detail, then use Suggestions from the Tags section.",
                recoverability: .userActionRequired,
                rawContext: pageID
            )
        }
    }

    var accessibilityIdentifier: String {
        "S2-15-C2-11-route-\(pageID)"
    }
}
