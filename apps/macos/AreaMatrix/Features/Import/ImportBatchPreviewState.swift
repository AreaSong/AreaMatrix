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
            "自动分类（推荐）"
        case let .category(slug):
            slug
        case .repositoryRoot:
            "Repo root"
        }
    }
}

enum ImportBatchPreviewRowStatus: Equatable {
    case loading
    case ready(reasonLabel: String)
    case duplicate(existingPath: String, reasonLabel: String)
    case nameConflict(existingPath: String, reasonLabel: String)
    case iCloudPlaceholder(path: String, reasonLabel: String)
    case blocked(String)
    case error(String)

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

    var detail: String? {
        switch self {
        case .loading:
            "Preparing preview..."
        case let .ready(reasonLabel), let .duplicate(_, reasonLabel), let .nameConflict(_, reasonLabel),
             let .iCloudPlaceholder(_, reasonLabel), let .blocked(reasonLabel), let .error(reasonLabel):
            reasonLabel
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
            predictedCategory ?? "未生成"
        case let .category(slug):
            slug
        case .repositoryRoot:
            "repo root"
        }
    }

    func withStatus(_ status: ImportBatchPreviewRowStatus) -> ImportBatchPreviewRow {
        var row = self
        row.status = status
        return row
    }

    static func loading(url: URL) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
            predictedCategory: nil,
            suggestedName: url.lastPathComponent,
            status: .loading
        )
    }

    static func ready(url: URL, prediction: ClassifyResultSnapshot) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
            predictedCategory: prediction.category,
            suggestedName: prediction.suggestedName.isEmpty ? url.lastPathComponent : prediction.suggestedName,
            status: .ready(reasonLabel: "\(prediction.reason.displayLabel) · \(prediction.confidencePercent)%")
        )
    }

    static func duplicate(
        url: URL,
        prediction: ClassifyResultSnapshot,
        existingPath: String
    ) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
            predictedCategory: prediction.category,
            suggestedName: prediction.suggestedName.isEmpty ? url.lastPathComponent : prediction.suggestedName,
            status: .duplicate(existingPath: existingPath, reasonLabel: "Skip: \(existingPath)")
        )
    }

    static func nameConflict(
        url: URL,
        prediction: ClassifyResultSnapshot,
        existingPath: String
    ) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
            predictedCategory: prediction.category,
            suggestedName: prediction.suggestedName.isEmpty ? url.lastPathComponent : prediction.suggestedName,
            status: .nameConflict(existingPath: existingPath, reasonLabel: "Keep both (auto-number): \(existingPath)")
        )
    }

    static func iCloudPlaceholder(url: URL, message: String) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: nil,
            predictedCategory: nil,
            suggestedName: url.lastPathComponent,
            status: .iCloudPlaceholder(path: url.path, reasonLabel: message)
        )
    }

    static func failed(url: URL, message: String) -> ImportBatchPreviewRow {
        ImportBatchPreviewRow(
            originalName: url.lastPathComponent,
            sourcePath: (url.path as NSString).abbreviatingWithTildeInPath,
            sizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
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
    case unsupported(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            nil
        case let .loading(completed, total):
            total > 0 ? "Preparing preview... \(completed)/\(total)" : "Preparing preview..."
        case let .loaded(successful, total, failed):
            loadedMessage(successful: successful, total: total, failed: failed)
        case let .unsupported(message):
            message
        }
    }

    private func loadedMessage(successful: Int, total: Int, failed: Int) -> String {
        if failed == 0 {
            return "已完成 \(total) 个文件的导入预览"
        }
        if successful == 0 {
            return "未能完成导入预览：\(failed) 个文件失败"
        }
        let failedPart = failed > 0 ? "，\(failed) 个失败" : ""
        return "已完成 \(successful)/\(total) 个文件的导入预览\(failedPart)"
    }
}

extension ImportEntrySource {
    var batchSourceLabel: String {
        switch self {
        case .filePicker: "Finder 选择"
        case .dropZone: "Finder 拖入"
        case .dockOpenFile: "Dock 打开"
        case .importConflictBatch: "Import conflict batch"
        }
    }
}

extension [ImportBatchDestinationOption] {
    func uniqued() -> [ImportBatchDestinationOption] {
        var seen = Set<ImportBatchDestinationOption>()
        return filter { seen.insert($0).inserted }
    }
}
