import Combine
import Foundation

enum ImportDropTarget: Equatable, Sendable {
    case autoClassify
    case category(String)
    case repositoryRoot

    var entryDestination: ImportEntryDestination {
        switch self {
        case .autoClassify:
            return .autoClassify
        case .category(let slug):
            return .category(slug)
        case .repositoryRoot:
            return .repositoryRoot
        }
    }

    var explicitLabel: String {
        switch self {
        case .autoClassify:
            return "Auto classify"
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return "repo root"
        }
    }

    var sidebarHelp: String {
        switch self {
        case .autoClassify:
            return "Import with automatic classification"
        case .category(let slug):
            return "Import into \"\(slug)\""
        case .repositoryRoot:
            return "Import into repository root"
        }
    }

    func destinationLabel(prediction: ClassifyResultSnapshot?) -> String {
        guard case .autoClassify = self, let prediction else {
            return explicitLabel
        }

        return prediction.category
    }
}

struct ImportDropPreviewPresentation: Equatable, Sendable {
    var target: ImportDropTarget
    var kind: ImportEntryKind
    var itemCount: Int
    var prediction: ClassifyResultSnapshot?
    var warning: String?
    var isPredicting: Bool

    var headline: String {
        kind.dropHoverTitle
    }

    var destinationLabel: String {
        target.destinationLabel(prediction: prediction)
    }

    var predictionLabel: String? {
        guard let prediction else { return nil }

        return "Classification preview: \(prediction.category) · " +
            "\(prediction.reason.displayLabel) · \(prediction.confidencePercent)%"
    }
}

@MainActor
final class ImportDropPreviewModel: ObservableObject {
    @Published private(set) var presentation: ImportDropPreviewPresentation?

    private let repoPath: String
    private let predictor: any CoreCategoryPredicting
    private var generation = 0

    init(repoPath: String, predictor: any CoreCategoryPredicting) {
        self.repoPath = repoPath
        self.predictor = predictor
    }

    func preview(target: ImportDropTarget, urls: [URL]) async {
        generation += 1
        let currentGeneration = generation
        let validURLs = Self.validFileURLs(from: urls)

        guard let firstURL = validURLs.first else {
            presentation = ImportDropPreviewPresentation(
                target: target,
                kind: .singleFile,
                itemCount: 0,
                prediction: nil,
                warning: "Cannot import this item",
                isPredicting: false
            )
            return
        }

        let warning = validURLs.count == urls.count ? nil : "Some items cannot be imported"
        let kind = ImportEntryKind.resolved(for: validURLs)
        let shouldPredictCategory = target == .autoClassify
        presentation = ImportDropPreviewPresentation(
            target: target,
            kind: kind,
            itemCount: validURLs.count,
            prediction: nil,
            warning: warning,
            isPredicting: shouldPredictCategory
        )

        guard shouldPredictCategory else { return }

        do {
            let prediction = try await predictor.predictCategory(
                repoPath: repoPath,
                filename: firstURL.lastPathComponent
            )
            guard generation == currentGeneration else { return }
            presentation = ImportDropPreviewPresentation(
                target: target,
                kind: kind,
                itemCount: validURLs.count,
                prediction: prediction,
                warning: warning,
                isPredicting: false
            )
        } catch {
            guard generation == currentGeneration else { return }
            presentation = ImportDropPreviewPresentation(
                target: target,
                kind: kind,
                itemCount: validURLs.count,
                prediction: nil,
                warning: Self.classifyWarning(for: error),
                isPredicting: false
            )
        }
    }

    func clear() {
        generation += 1
        presentation = nil
    }

    private static func validFileURLs(from urls: [URL]) -> [URL] {
        urls.filter { url in
            url.isFileURL && !url.path.isEmpty
        }
    }

    private static func classifyWarning(for error: Error) -> String {
        guard let coreError = error as? CoreError else {
            return "Cannot preview category"
        }

        switch coreError {
        case .Config(let reason):
            return "Classifier settings are invalid: \(reason)"
        case .Classify(let reason):
            return "Cannot preview category: \(reason)"
        default:
            return "Cannot preview category"
        }
    }
}

extension RepositorySidebarRowSnapshot {
    var importDropTarget: ImportDropTarget {
        if node.slug == "__root__" || node.relativePath.isEmpty {
            return .repositoryRoot
        }

        return .category(categoryForFileList ?? node.slug)
    }
}

enum ImportBatchDestinationOption: Hashable, Sendable {
    case autoClassify
    case category(String)
    case repositoryRoot

    var title: String {
        switch self {
        case .autoClassify:
            return "自动分类（推荐）"
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return "Repo root"
        }
    }
}

enum ImportBatchPreviewRowStatus: Equatable, Sendable {
    case loading
    case ready(reasonLabel: String)
    case error(String)

    var tag: String {
        switch self {
        case .loading:
            return "PREVIEW"
        case .ready:
            return "OK"
        case .error:
            return "ERROR"
        }
    }

    var detail: String? {
        switch self {
        case .loading:
            return "Preparing preview..."
        case .ready(let reasonLabel), .error(let reasonLabel):
            return reasonLabel
        }
    }

    var isReady: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}

struct ImportBatchPreviewRow: Identifiable, Equatable, Sendable {
    var originalName: String
    var sourcePath: String
    var sizeBytes: Int64?
    var predictedCategory: String?
    var suggestedName: String
    var status: ImportBatchPreviewRowStatus

    var id: String { sourcePath }

    func displayCategory(for destination: ImportBatchDestinationOption) -> String {
        switch destination {
        case .autoClassify:
            return predictedCategory ?? "未生成"
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return "repo root"
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

enum ImportBatchPreviewStatus: Equatable, Sendable {
    case idle
    case loading(completed: Int, total: Int)
    case loaded(successful: Int, total: Int, failed: Int)
    case unsupported(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .loading(let completed, let total):
            return total > 0 ? "Preparing preview... \(completed)/\(total)" : "Preparing preview..."
        case .loaded(let successful, let total, let failed):
            if failed == 0 {
                return "已完成 \(total) 个文件的分类预览"
            }
            if successful == 0 {
                return "未能完成分类预览：\(failed) 个文件失败"
            }
            return "已完成 \(successful)/\(total) 个文件的分类预览，\(failed) 个失败"
        case .unsupported(let message):
            return message
        }
    }
}

@MainActor
final class ImportBatchPreviewModel: ObservableObject {
    @Published private(set) var rows: [ImportBatchPreviewRow] = []
    @Published private(set) var status: ImportBatchPreviewStatus = .idle
    @Published var selectedDestination: ImportBatchDestinationOption = .autoClassify

    private let predictor: any CoreCategoryPredicting
    private var request: ImportEntryRequest?
    private var generation = 0

    init(predictor: any CoreCategoryPredicting) {
        self.predictor = predictor
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
        rows.filter { $0.status.isReady }.count
    }

    var failedPreviewCount: Int {
        rows.filter { $0.status.isError }.count
    }

    var showsRetryPreview: Bool {
        failedPreviewCount > 0 && !status.isLoading
    }

    var importDisabledReason: String {
        if status.isLoading {
            return "Preparing preview..."
        }
        return "本任务仅接入 C1-05 classify-preview；批量导入执行与冲突处理将在后续任务接入。"
    }

    var destinationHelperMessage: String? {
        switch selectedDestination {
        case .autoClassify:
            return nil
        case .category:
            return "已覆盖自动分类结果；当前任务仍保留每个文件的分类建议作为参考。"
        case .repositoryRoot:
            return "当前入口保留在资料库根目录；分类建议只作为预览，不会自动写入。"
        }
    }

    func load(request: ImportEntryRequest) async {
        generation += 1
        let currentGeneration = generation
        self.request = request

        guard case .multipleItems = request.kind, request.urls.count > 1 else {
            rows = []
            status = .unsupported("此 sheet 只处理批量文件导入")
            return
        }

        selectedDestination = request.initialBatchDestination
        rows = request.urls.map(ImportBatchPreviewRow.loading)
        status = .loading(completed: 0, total: request.urls.count)

        var completed = 0
        for (index, url) in request.urls.enumerated() {
            do {
                let prediction = try await predictor.predictCategory(
                    repoPath: request.repoPath,
                    filename: url.lastPathComponent
                )
                guard generation == currentGeneration else { return }
                rows[index] = .ready(url: url, prediction: prediction)
            } catch {
                guard generation == currentGeneration else { return }
                rows[index] = .failed(url: url, message: Self.classifyMessage(for: error))
            }
            completed += 1
            status = .loading(completed: completed, total: request.urls.count)
        }

        guard generation == currentGeneration else { return }
        status = .loaded(
            successful: successfulPreviewCount,
            total: rows.count,
            failed: failedPreviewCount
        )
    }

    func retryPreview() async {
        guard let request else { return }
        await load(request: request)
    }

    private static func classifyMessage(for error: Error) -> String {
        guard let coreError = error as? CoreError else {
            return "无法预览分类"
        }

        switch coreError {
        case .Config(let reason):
            return "分类规则无效：\(reason)"
        case .Classify(let reason):
            return "无法预览分类：\(reason)"
        default:
            return "无法预览分类"
        }
    }
}

private extension ImportEntryRequest {
    var initialBatchDestination: ImportBatchDestinationOption {
        switch destination {
        case .autoClassify:
            return .autoClassify
        case .category(let slug):
            return .category(slug)
        case .repositoryRoot:
            return .repositoryRoot
        }
    }
}

private extension ImportEntrySource {
    var batchSourceLabel: String {
        switch self {
        case .filePicker:
            return "Finder 选择"
        case .dropZone:
            return "Finder 拖入"
        case .dockOpenFile:
            return "Dock 打开"
        }
    }
}

private extension Array where Element == ImportBatchDestinationOption {
    func uniqued() -> [ImportBatchDestinationOption] {
        var seen = Set<ImportBatchDestinationOption>()
        return filter { seen.insert($0).inserted }
    }
}
