import Combine
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

@MainActor
final class ImportBatchPreviewModel: ObservableObject {
    @Published private(set) var rows: [ImportBatchPreviewRow] = []
    @Published private(set) var status: ImportBatchPreviewStatus = .idle
    @Published var selectedDestination: ImportBatchDestinationOption = .autoClassify

    private let predictor: any CoreCategoryPredicting
    private let duplicatePrechecker: (any ImportBatchDuplicatePrechecking)?
    private let nameConflictPrechecker: (any ImportBatchNameConflictPrechecking)?
    private var request: ImportEntryRequest?
    private var generation = 0

    init(
        predictor: any CoreCategoryPredicting,
        duplicatePrechecker: (any ImportBatchDuplicatePrechecking)? = nil,
        nameConflictPrechecker: (any ImportBatchNameConflictPrechecking)? = nil
    ) {
        self.predictor = predictor
        self.duplicatePrechecker = duplicatePrechecker
        self.nameConflictPrechecker = nameConflictPrechecker
    }

    var destinationOptions: [ImportBatchDestinationOption] {
        guard let request else {
            return [.autoClassify]
        }

        var options: [ImportBatchDestinationOption] = [.autoClassify]
        if request.destination == .repositoryRoot {
            options.append(.repositoryRoot)
        }
        options.append(contentsOf: request.availableCategories.map(ImportBatchDestinationOption.category))
        return options.uniqued()
    }

    var totalSizeDescription: String? {
        let total = rows.compactMap(\.sizeBytes).reduce(0, +)
        guard total > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var sourceLabel: String {
        request?.source.batchSourceLabel ?? "未知来源"
    }

    var successfulPreviewCount: Int {
        rows.filter(\.status.isPrepared).count
    }

    var failedPreviewCount: Int {
        rows.filter(\.status.isError).count
    }

    var showsRetryPreview: Bool {
        failedPreviewCount > 0 && !status.isLoading
    }

    var importDisabledReason: String? {
        if status.isLoading {
            return "Preparing preview..."
        }
        return nil
    }

    var destinationHelperMessage: String? {
        switch selectedDestination {
        case .autoClassify:
            nil
        case .category:
            "已覆盖自动分类结果；当前任务仍保留每个文件的分类建议作为参考。"
        case .repositoryRoot:
            "当前入口保留在资料库根目录；分类建议只作为预览，不会自动写入。"
        }
    }

    func load(request: ImportEntryRequest) async {
        generation += 1
        let currentGeneration = generation
        self.request = request

        if let route = request.importConflictBatchRoute {
            loadImportConflictBatchRoute(request: request, route: route)
            return
        }

        guard case .multipleItems = request.kind, request.urls.count > 1 else {
            rows = []
            status = .unsupported("此 sheet 只处理批量文件导入")
            return
        }

        selectedDestination = request.initialBatchDestination
        rows = request.urls.map(ImportBatchPreviewRow.loading)
        status = .loading(completed: 0, total: request.urls.count)
        await Task.yield()
        let duplicatePrecheck = await duplicatePrechecker?.precheckDuplicates(
            repoPath: request.repoPath,
            sourceURLs: request.urls,
            destination: selectedDestination
        ) ?? [:]

        var completed = 0
        var pendingRows = rows
        for (index, url) in request.urls.enumerated() {
            pendingRows[index] = await previewRow(
                url: url,
                request: request,
                duplicatePrecheck: duplicatePrecheck[url.path]
            )
            guard generation == currentGeneration else { return }
            completed += 1
            if shouldPublishPreviewProgress(completed: completed, total: request.urls.count) {
                rows = pendingRows
                status = .loading(completed: completed, total: request.urls.count)
                await Task.yield()
            }
        }

        rows = pendingRows
        status = .loading(completed: completed, total: request.urls.count)
        await applyNameConflictPrecheck(repoPath: request.repoPath, generation: currentGeneration)
        guard generation == currentGeneration else { return }
        status = .loaded(
            successful: successfulPreviewCount,
            total: rows.count,
            failed: failedPreviewCount
        )
    }

    private func loadImportConflictBatchRoute(
        request: ImportEntryRequest,
        route: ImportConflictBatchRoute
    ) {
        selectedDestination = request.initialBatchDestination
        let rowStatus = ImportBatchPreviewRowStatus.nameConflict(
            existingPath: "Core import session \(route.importSessionID)",
            reasonLabel: "Waiting for Core conflict batch preview"
        )
        rows = route.conflictIDs.map {
            ImportBatchPreviewRow(
                originalName: $0, sourcePath: $0, sizeBytes: nil, predictedCategory: nil,
                suggestedName: $0, status: rowStatus
            )
        }
        status = .loaded(successful: rows.count, total: rows.count, failed: 0)
    }

    func retryPreview() async {
        guard let request else { return }
        await load(request: request)
    }

    private func previewRow(
        url: URL,
        request: ImportEntryRequest,
        duplicatePrecheck: ImportBatchDuplicatePrecheckResult?
    ) async -> ImportBatchPreviewRow {
        do {
            let prediction = try await predictor.predictCategory(
                repoPath: request.repoPath,
                filename: url.lastPathComponent
            )
            if let duplicatePrecheck {
                return row(url: url, prediction: prediction, duplicatePrecheck: duplicatePrecheck)
            }
            return .ready(url: url, prediction: prediction)
        } catch {
            return .failed(url: url, message: Self.previewMessage(for: error))
        }
    }

    private func applyNameConflictPrecheck(repoPath: String, generation currentGeneration: Int) async {
        guard let nameConflictPrechecker else { return }
        let eligibleRows = rows.filter(\.canRunNameConflictPrecheck)
        guard !eligibleRows.isEmpty else { return }

        let conflicts = await nameConflictPrechecker.precheckNameConflicts(
            repoPath: repoPath,
            rows: eligibleRows,
            destination: selectedDestination
        )
        guard generation == currentGeneration else { return }

        rows = rows.map { row in
            guard let conflict = conflicts[row.id] else { return row }
            switch conflict {
            case let .conflict(existingPath):
                return row.withStatus(.nameConflict(
                    existingPath: existingPath,
                    reasonLabel: "Keep both (auto-number): \(existingPath)"
                ))
            case let .failed(message):
                return row.withStatus(.error(message))
            }
        }
    }

    private func row(
        url: URL,
        prediction: ClassifyResultSnapshot,
        duplicatePrecheck: ImportBatchDuplicatePrecheckResult
    ) -> ImportBatchPreviewRow {
        switch duplicatePrecheck {
        case let .duplicate(existingPath):
            .duplicate(url: url, prediction: prediction, existingPath: existingPath)
        case let .nameConflict(existingPath):
            .nameConflict(url: url, prediction: prediction, existingPath: existingPath)
        case .iCloudPlaceholder:
            .iCloudPlaceholder(url: url, message: "iCloud placeholder 需要下载后才能导入")
        case let .blocked(message):
            .failed(url: url, message: message)
        case let .failed(message):
            .failed(url: url, message: message)
        }
    }

    private func shouldPublishPreviewProgress(completed: Int, total: Int) -> Bool {
        completed == total || completed == 1 || completed.isMultiple(of: 10)
    }

    private static func previewMessage(for error: Error) -> String {
        guard let coreError = error as? CoreError else {
            return "无法完成分类预览"
        }

        switch coreError {
        case let .Config(reason):
            return "分类规则无效：\(reason)"
        case let .Classify(reason):
            return "无法预览分类：\(reason)"
        case let .PermissionDenied(path):
            return "无法读取分类预览路径：\(path)"
        case let .Io(message):
            return "分类预览文件读取失败：\(message)"
        case let .Db(message):
            return "分类预览数据库读取失败：\(message)"
        default:
            return "无法完成分类预览"
        }
    }
}

private extension ImportBatchPreviewRow {
    var canRunNameConflictPrecheck: Bool {
        switch status {
        case .ready:
            true
        case .loading, .duplicate, .nameConflict, .iCloudPlaceholder, .blocked, .error:
            false
        }
    }

    func withStatus(_ status: ImportBatchPreviewRowStatus) -> ImportBatchPreviewRow {
        var row = self
        row.status = status
        return row
    }
}

private extension ImportEntrySource {
    var batchSourceLabel: String {
        switch self {
        case .filePicker: "Finder 选择"
        case .dropZone: "Finder 拖入"
        case .dockOpenFile: "Dock 打开"
        case .importConflictBatch: "Import conflict batch"
        }
    }
}

private extension [ImportBatchDestinationOption] {
    func uniqued() -> [ImportBatchDestinationOption] {
        var seen = Set<ImportBatchDestinationOption>()
        return filter { seen.insert($0).inserted }
    }
}
