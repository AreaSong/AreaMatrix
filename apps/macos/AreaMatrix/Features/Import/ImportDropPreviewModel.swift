import Combine
import Foundation

enum ImportDropTarget: Equatable {
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

    var explicitLabel: String {
        switch self {
        case .autoClassify:
            L10n.string("Auto classify")
        case let .category(slug):
            slug
        case .repositoryRoot:
            L10n.string("repo root")
        }
    }

    var sidebarHelp: String {
        switch self {
        case .autoClassify:
            L10n.string("Import with automatic classification")
        case let .category(slug):
            L10n.format("import.drop.import-into-category", slug)
        case .repositoryRoot:
            L10n.string("Import into repository root")
        }
    }

    func destinationLabel(prediction: ClassifyResultSnapshot?) -> String {
        guard case .autoClassify = self, let prediction else {
            return explicitLabel
        }

        return prediction.category
    }
}

struct ImportDropPreviewPresentation: Equatable {
    var target: ImportDropTarget
    var kind: ImportEntryKind
    var itemCount: Int
    var prediction: ClassifyResultSnapshot?
    var warning: AppDisplayText?
    var isPredicting: Bool

    var headline: String {
        kind.dropHoverTitle
    }

    var destinationLabel: String {
        target.destinationLabel(prediction: prediction)
    }

    var predictionLabel: String? {
        guard let prediction else { return nil }

        return L10n.format(
            "import.drop.classification-preview",
            prediction.category,
            prediction.reason.displayLabel,
            Int64(prediction.confidencePercent)
        )
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
            presentation = emptyPresentation(for: target)
            return
        }

        let warning = validURLs.count == urls.count ? nil : L10n.display("Some items cannot be imported")
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
            presentation = predictedPresentation(
                target: target,
                kind: kind,
                count: validURLs.count,
                prediction: prediction,
                warning: warning
            )
        } catch {
            guard generation == currentGeneration else { return }
            presentation = failedPredictionPresentation(
                target: target,
                kind: kind,
                count: validURLs.count,
                error: error
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

    private func emptyPresentation(for target: ImportDropTarget) -> ImportDropPreviewPresentation {
        ImportDropPreviewPresentation(
            target: target,
            kind: .singleFile,
            itemCount: 0,
            prediction: nil,
            warning: L10n.display("Cannot import this item"),
            isPredicting: false
        )
    }

    private func predictedPresentation(
        target: ImportDropTarget,
        kind: ImportEntryKind,
        count: Int,
        prediction: ClassifyResultSnapshot,
        warning: AppDisplayText?
    ) -> ImportDropPreviewPresentation {
        ImportDropPreviewPresentation(
            target: target,
            kind: kind,
            itemCount: count,
            prediction: prediction,
            warning: warning,
            isPredicting: false
        )
    }

    private func failedPredictionPresentation(
        target: ImportDropTarget,
        kind: ImportEntryKind,
        count: Int,
        error: Error
    ) -> ImportDropPreviewPresentation {
        ImportDropPreviewPresentation(
            target: target,
            kind: kind,
            itemCount: count,
            prediction: nil,
            warning: Self.classifyWarning(for: error),
            isPredicting: false
        )
    }

    private static func classifyWarning(for error: Error) -> AppDisplayText {
        guard let context = CoreErrorRawContextSnapshot(error) else {
            return L10n.display(
                "Cannot preview category",
                technicalDetail: error.localizedDescription
            )
        }

        switch context.kind {
        case .config, .classify:
            return L10n.display("Cannot preview category", technicalDetail: context.rawContext)
        default:
            return L10n.display("Cannot preview category", technicalDetail: context.rawContext)
        }
    }
}

extension RepositorySidebarRowSnapshot {
    var importDropTarget: ImportDropTarget {
        if isSmartList {
            return .repositoryRoot
        }
        if node.slug == "__root__" || node.relativePath.isEmpty {
            return .repositoryRoot
        }

        return .category(categoryForFileList ?? node.slug)
    }
}
