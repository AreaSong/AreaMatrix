import Combine
import Foundation

struct ImportSingleFileSource: Equatable, Sendable {
    var fileName: String
    var sourcePath: String

    init(url: URL) {
        fileName = url.lastPathComponent
        sourcePath = (url.path as NSString).abbreviatingWithTildeInPath
    }
}

enum ImportSingleFilePreviewStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
    case unsupported(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .loading:
            return "正在预览分类..."
        case .ready:
            return "分类预览完成"
        case .failed(let message), .unsupported(let message):
            return message
        }
    }
}

enum ImportSingleFileImportStatus: Equatable, Sendable {
    case idle
    case importing(ImportSingleFileStorageMode)
    case imported(FileEntrySnapshot)
    case failed(CoreErrorMappingSnapshot)
    case blocked(String)

    var isImporting: Bool {
        if case .importing = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .importing(let mode):
            return mode.importingMessage
        case .imported(let entry):
            return "已导入：\(entry.currentName)"
        case .failed(let mapping):
            return mapping.userMessage
        case .blocked(let message):
            return message
        }
    }
}

enum ImportSingleFileStorageMode: String, CaseIterable, Equatable, Identifiable, Sendable {
    case copy = "Copy"
    case move = "Move"
    case indexOnly = "Index-only"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .copy:
            return "保留原文件，复制到 AreaMatrix 资料库。"
        case .move:
            return "源文件会从原位置移走，并安全写入 AreaMatrix 资料库。"
        case .indexOnly:
            return "不复制，只记录引用路径；源文件移动后会缺失。"
        }
    }

    var importingMessage: String {
        switch self {
        case .copy:
            return "正在复制导入..."
        case .move:
            return "正在移动导入..."
        case .indexOnly:
            return "正在写入索引..."
        }
    }

    var importingBlockingMessage: String {
        switch self {
        case .copy:
            return "正在复制导入"
        case .move:
            return "正在移动导入"
        case .indexOnly:
            return "正在写入索引"
        }
    }
}

@MainActor
final class ImportSingleFilePreviewModel: ObservableObject {
    @Published private(set) var source: ImportSingleFileSource?
    @Published private(set) var prediction: ClassifyResultSnapshot?
    @Published private(set) var status: ImportSingleFilePreviewStatus = .idle
    @Published private(set) var importStatus: ImportSingleFileImportStatus = .idle
    @Published var selectedCategory = "inbox"
    @Published var suggestedName = ""
    @Published var selectedStorageMode: ImportSingleFileStorageMode = .copy

    private let predictor: any CoreCategoryPredicting
    private let importer: any CoreFileImporting
    private let errorMapper: any CoreErrorMapping
    private var request: ImportEntryRequest?
    private var generation = 0

    init(
        predictor: any CoreCategoryPredicting,
        importer: any CoreFileImporting,
        errorMapper: any CoreErrorMapping
    ) {
        self.predictor = predictor
        self.importer = importer
        self.errorMapper = errorMapper
    }

    var reasonSummary: String {
        guard let prediction else { return "暂无分类解释" }
        return "\(prediction.reason.displayLabel) · \(prediction.confidencePercent)%"
    }

    var importDisabledReason: String? {
        if importStatus.isImporting {
            return importStatus.blockingMessage ?? "正在导入"
        }
        if !isReadyForImport {
            return status.message ?? "导入预检未完成"
        }
        if selectedCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请选择导入分类"
        }
        if suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请输入导入文件名"
        }
        return nil
    }

    func load(request: ImportEntryRequest) async {
        generation += 1
        let currentGeneration = generation
        self.request = request
        importStatus = .idle

        guard request.kind == .singleFile, request.urls.count == 1, let sourceURL = request.urls.first else {
            resetForUnsupportedRequest("此 sheet 只处理单文件导入")
            return
        }

        source = ImportSingleFileSource(url: sourceURL)
        prediction = nil
        status = .loading
        selectedStorageMode = .copy
        selectedCategory = request.explicitCategory ?? "inbox"
        suggestedName = sourceURL.lastPathComponent

        do {
            let result = try await predictor.predictCategory(
                repoPath: request.repoPath,
                filename: sourceURL.lastPathComponent
            )
            guard generation == currentGeneration else { return }
            applyPrediction(result, request: request, fallbackName: sourceURL.lastPathComponent)
        } catch {
            guard generation == currentGeneration else { return }
            prediction = nil
            status = .failed(Self.classifyMessage(for: error))
        }
    }

    func importSelectedFile() async {
        guard let request, let sourceURL = request.urls.first else {
            importStatus = .blocked("没有可导入的单文件来源")
            return
        }
        if let disabledReason = importDisabledReason {
            importStatus = .blocked(disabledReason)
            return
        }

        importStatus = .importing(selectedStorageMode)
        do {
            let entry = try await importFile(
                repoPath: request.repoPath,
                sourceURL: sourceURL,
                overrideCategory: selectedCategory.trimmingCharacters(in: .whitespacesAndNewlines),
                overrideFilename: suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            importStatus = .imported(entry)
        } catch {
            importStatus = .failed(await mapImportError(error))
        }
    }

    private func resetForUnsupportedRequest(_ message: String) {
        source = nil
        prediction = nil
        selectedCategory = "inbox"
        suggestedName = ""
        selectedStorageMode = .copy
        status = .unsupported(message)
        importStatus = .idle
    }

    private func applyPrediction(
        _ result: ClassifyResultSnapshot,
        request: ImportEntryRequest,
        fallbackName: String
    ) {
        prediction = result
        if request.explicitCategory == nil || selectedCategory.isEmpty {
            selectedCategory = result.category
        }
        suggestedName = result.suggestedName.isEmpty ? fallbackName : result.suggestedName
        status = .ready
    }

    private var isReadyForImport: Bool {
        guard case .ready = status else { return false }
        return true
    }

    private func importFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        switch selectedStorageMode {
        case .copy:
            return try await importer.importCopiedFile(
                repoPath: repoPath,
                sourceURL: sourceURL,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename
            )
        case .move:
            return try await importer.importMovedFile(
                repoPath: repoPath,
                sourceURL: sourceURL,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename
            )
        case .indexOnly:
            return try await importer.importIndexedFile(
                repoPath: repoPath,
                sourceURL: sourceURL,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename
            )
        }
    }

    private func mapImportError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
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

private extension ImportSingleFileImportStatus {
    var blockingMessage: String? {
        guard case .importing(let mode) = self else { return nil }
        return mode.importingBlockingMessage
    }
}

private extension ImportEntryRequest {
    var explicitCategory: String? {
        guard case .category(let slug) = destination else { return nil }
        return slug
    }
}
