import AreaMatrixFeatureIngestion
import Foundation

enum ImportBatchDestinationOption: Hashable {
    case autoClassify
    case category(String)
    case repositoryRoot

    var entryDestination: ImportEntryDestination {
        switch self {
        case .autoClassify:
            .autoClassify
        case let .category(slug):
            .category(slug)
        case .repositoryRoot:
            .repositoryRoot
        }
    }

    var title: String {
        switch self {
        case .autoClassify:
            L10n.string("自动分类（推荐）")
        case let .category(slug):
            slug
        case .repositoryRoot:
            L10n.string("Repo root")
        }
    }
}

enum ImportBatchPreviewRowStatus: Equatable {
    case loading
    case ready(reasonLabel: AppDisplayText)
    case duplicate(existingPath: String, reasonLabel: AppDisplayText)
    case nameConflict(existingPath: String, reasonLabel: AppDisplayText)
    case iCloudPlaceholder(path: String, reasonLabel: AppDisplayText)
    case blocked(AppDisplayText)
    case error(AppDisplayText)

    var tag: String {
        switch self {
        case .loading:
            "PREVIEW"
        case .ready:
            "OK"
        case .duplicate:
            "DUP"
        case .nameConflict:
            "NAME"
        case .iCloudPlaceholder:
            "ICLOUD"
        case .blocked:
            "BLOCKED"
        case .error:
            "ERROR"
        }
    }

    var tagMessage: LocalizedMessage {
        ImportStatusTagLocalization.message(for: tag)
    }

    var detail: String? {
        switch self {
        case .loading:
            L10n.string("Preparing preview...")
        case let .ready(reasonLabel), let .duplicate(_, reasonLabel), let .nameConflict(_, reasonLabel),
             let .iCloudPlaceholder(_, reasonLabel), let .blocked(reasonLabel), let .error(reasonLabel):
            L10n.resolve(reasonLabel)
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isPrepared: Bool {
        switch self {
        case .ready, .duplicate, .nameConflict:
            true
        case .loading, .iCloudPlaceholder, .blocked, .error:
            false
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        if case .blocked = self { return true }
        return false
    }
}

struct ImportBatchPreviewRow: Identifiable, Equatable {
    var originalName: String
    var sourcePath: String
    var sizeBytes: Int64?
    var predictedCategory: String?
    var suggestedName: String
    var status: ImportBatchPreviewRowStatus

    var id: String {
        sourcePath
    }

    var canRunNameConflictPrecheck: Bool {
        switch status {
        case .ready:
            true
        case .loading, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .error:
            false
        }
    }

    func displayCategory(for destination: ImportBatchDestinationOption) -> String {
        switch destination {
        case .autoClassify:
            predictedCategory ?? L10n.string("未生成")
        case let .category(slug):
            slug
        case .repositoryRoot:
            L10n.string("repo root")
        }
    }

    func withStatus(_ status: ImportBatchPreviewRowStatus) -> ImportBatchPreviewRow {
        var row = self
        row.status = status
        return row
    }

    static func loading(url: URL, sizeBytes: Int64? = nil) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: sizeBytes,
            predictedCategory: nil,
            suggestedName: url.lastPathComponent,
            status: .loading
        )
    }

    static func ready(
        url: URL,
        prediction: ClassifyResultSnapshot,
        sizeBytes: Int64? = nil
    ) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: sizeBytes,
            predictedCategory: prediction.category,
            suggestedName: prediction.suggestedName.isEmpty ? url.lastPathComponent : prediction.suggestedName,
            status: .ready(
                reasonLabel: L10n.display(
                    "import.preview.classification-reason",
                    arguments: [
                        .string(prediction.reason.displayLabel),
                        .integer64(Int64(prediction.confidencePercent))
                    ]
                )
            )
        )
    }

    static func duplicate(
        url: URL,
        prediction: ClassifyResultSnapshot,
        existingPath: String,
        sizeBytes: Int64? = nil
    ) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: sizeBytes,
            predictedCategory: prediction.category,
            suggestedName: prediction.suggestedName.isEmpty ? url.lastPathComponent : prediction.suggestedName,
            status: .duplicate(
                existingPath: existingPath,
                reasonLabel: L10n.display(
                    "import.preview.duplicate-skip",
                    arguments: [.string(existingPath)]
                )
            )
        )
    }

    static func nameConflict(
        url: URL,
        prediction: ClassifyResultSnapshot,
        existingPath: String,
        sizeBytes: Int64? = nil
    ) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: sizeBytes,
            predictedCategory: prediction.category,
            suggestedName: prediction.suggestedName.isEmpty ? url.lastPathComponent : prediction.suggestedName,
            status: .nameConflict(
                existingPath: existingPath,
                reasonLabel: L10n.display(
                    "import.preview.keep-both-auto-number",
                    arguments: [.string(existingPath)]
                )
            )
        )
    }

    static func iCloudPlaceholder(
        url: URL,
        message: AppDisplayText,
        sizeBytes: Int64? = nil
    ) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: sizeBytes,
            predictedCategory: nil,
            suggestedName: url.lastPathComponent,
            status: .iCloudPlaceholder(path: url.path, reasonLabel: message)
        )
    }

    static func failed(
        url: URL,
        message: AppDisplayText,
        sizeBytes: Int64? = nil
    ) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: sizeBytes,
            predictedCategory: nil,
            suggestedName: url.lastPathComponent,
            status: .error(message)
        )
    }
}

enum ImportBatchPreviewStatus: Equatable {
    case idle
    case loading(completed: Int, total: Int)
    case loaded(successful: Int, total: Int, failed: Int)
    case unsupported(AppDisplayText)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            nil
        case let .loading(completed, total):
            if total > 0 {
                L10n.format("import.preview.preparingProgress", completed, total)
            } else {
                L10n.string("Preparing preview...")
            }
        case let .loaded(successful, total, failed):
            loadedMessage(successful: successful, total: total, failed: failed)
        case let .unsupported(message):
            L10n.resolve(message)
        }
    }

    private func loadedMessage(successful: Int, total: Int, failed: Int) -> String {
        if failed == 0 {
            return L10n.plural("import.preview.completed-files", count: total)
        }
        if successful == 0 {
            return L10n.plural("import.preview.failed-files", count: failed)
        }
        return L10n.format("import.preview.completedWithFailures", successful, total, failed)
    }
}

extension ImportEntrySource {
    var batchSourceLabel: String {
        switch self {
        case .filePicker: L10n.string("import.source.finderSelection")
        case .dropZone: L10n.string("import.source.finderDrop")
        case .dockOpenFile: L10n.string("import.source.dockOpen")
        case .importConflictBatch: L10n.string("import.source.conflictBatch")
        }
    }
}

extension [ImportBatchDestinationOption] {
    func uniqued() -> [ImportBatchDestinationOption] {
        var seen = Set<ImportBatchDestinationOption>()
        return filter { seen.insert($0).inserted }
    }
}
