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
