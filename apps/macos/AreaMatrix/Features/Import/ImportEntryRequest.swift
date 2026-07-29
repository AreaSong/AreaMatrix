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
            L10n.string("Import folder")
        case .singleFile:
            L10n.plural("import.entry.sheet-title", count: 1)
        case let .multipleItems(count):
            L10n.plural("import.entry.sheet-title", count: count)
        }
    }

    var destinationLabel: String {
        switch destination {
        case .autoClassify:
            L10n.string("Auto classify")
        case let .category(slug):
            slug
        case .repositoryRoot:
            L10n.string("Repo root")
        }
    }

    var importConflictBatchRoute: ImportConflictBatchRoute? {
        guard let importSessionID else { return nil }
        let conflictIDs = importConflictIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !conflictIDs.isEmpty else { return nil }
        let sourceRoute: CommandPaletteLinkedPageRoute? = if case let .importConflictBatch(route) = source {
            route
        } else {
            nil
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
    static func resolved(
        for urls: [URL],
        isDirectory: (URL) -> Bool = ImportPlatformServices.isDirectory
    ) -> ImportEntryKind {
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
            L10n.string("Drop folder to import recursively")
        case .singleFile:
            L10n.string("Drop files to import")
        case let .multipleItems(count):
            L10n.plural("import.entry.drop-files", count: count)
        }
    }
}

enum CommandPaletteLinkedPageRoute: String, Equatable, Identifiable, CaseIterable {
    case classifierImpactPreview = "classifier-impact-preview"
    case importConflictBatch = "import-conflict-batch"
    case redo = "redo-action-log"
    case tagSuggestions = "tag-suggestions"

    var id: String {
        rawValue
    }

    var pageID: String {
        rawValue
    }

    var blockedMapping: CoreErrorMappingSnapshot {
        switch self {
        case .classifierImpactPreview:
            CoreErrorMappingSnapshot(
                kind: .validation,
                userMessage: L10n.message("Classifier impact preview is not available yet."),
                severity: .medium,
                suggestedAction: L10n.message(
                    "Open classifier rules first, then preview how the rule affects existing files."
                ),
                recoverability: .userActionRequired,
                rawContext: pageID
            )
        case .importConflictBatch:
            CoreErrorMappingSnapshot(
                kind: .stagingRecoveryRequired,
                userMessage: L10n.message("There is no active import conflict batch to review."),
                severity: .medium,
                suggestedAction: L10n.message("Start or resume a batch import with unresolved conflicts."),
                recoverability: .userActionRequired,
                rawContext: pageID
            )
        case .redo:
            CoreErrorMappingSnapshot(
                kind: .conflict,
                userMessage: L10n.message("Redo latest is handled in Undo History."),
                severity: .medium,
                suggestedAction: L10n.message("Review Undo History until redo-action-log redo is available."),
                recoverability: .refreshRequired,
                rawContext: pageID
            )
        case .tagSuggestions:
            CoreErrorMappingSnapshot(
                kind: .validation,
                userMessage: L10n.message("Select a file before reviewing tag suggestions."),
                severity: .medium,
                suggestedAction: L10n.message("Open a file detail, then use Suggestions from the Tags section."),
                recoverability: .userActionRequired,
                rawContext: pageID
            )
        }
    }

    var accessibilityIdentifier: String {
        "command-palette-command-index-route-\(pageID)"
    }
}
