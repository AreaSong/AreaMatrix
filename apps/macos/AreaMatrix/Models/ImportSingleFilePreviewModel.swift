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

@MainActor
final class ImportSingleFilePreviewModel: ObservableObject {
    @Published private(set) var source: ImportSingleFileSource?
    @Published private(set) var prediction: ClassifyResultSnapshot?
    @Published private(set) var status: ImportSingleFilePreviewStatus = .idle
    @Published var selectedCategory = "inbox"
    @Published var suggestedName = ""

    private let predictor: any CoreCategoryPredicting
    private var generation = 0

    init(predictor: any CoreCategoryPredicting) {
        self.predictor = predictor
    }

    var reasonSummary: String {
        guard let prediction else { return "暂无分类解释" }
        return "\(prediction.reason.displayLabel) · \(prediction.confidencePercent)%"
    }

    func load(request: ImportEntryRequest) async {
        generation += 1
        let currentGeneration = generation

        guard request.kind == .singleFile, request.urls.count == 1, let sourceURL = request.urls.first else {
            resetForUnsupportedRequest("此 sheet 只处理单文件导入")
            return
        }

        source = ImportSingleFileSource(url: sourceURL)
        prediction = nil
        status = .loading
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

    private func resetForUnsupportedRequest(_ message: String) {
        source = nil
        prediction = nil
        selectedCategory = "inbox"
        suggestedName = ""
        status = .unsupported(message)
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
    var explicitCategory: String? {
        guard case .category(let slug) = destination else { return nil }
        return slug
    }
}
