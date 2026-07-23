import Combine
import Foundation

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
        request?.source.batchSourceLabel ?? L10n.string("import.source.unknown")
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
            return L10n.string("Preparing preview...")
        }
        return nil
    }

    var destinationHelperMessage: String? {
        switch selectedDestination {
        case .autoClassify:
            nil
        case .category:
            L10n.string("import.batch.destination.categoryOverrideHelp")
        case .repositoryRoot:
            L10n.string("import.batch.destination.repositoryRootHelp")
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
            status = .unsupported(L10n.display("import.batch.unsupportedRequest"))
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
            reasonLabel: L10n.display("Waiting for Core conflict batch preview")
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
                    reasonLabel: L10n.display(
                        "import.preview.keep-both-auto-number",
                        arguments: [.string(existingPath)]
                    )
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
            .iCloudPlaceholder(url: url, message: L10n.display("import.icloud.downloadRequired"))
        case let .blocked(message):
            .failed(url: url, message: message)
        case let .failed(message):
            .failed(url: url, message: message)
        }
    }

    private func shouldPublishPreviewProgress(completed: Int, total: Int) -> Bool {
        completed == total || completed == 1 || completed.isMultiple(of: 10)
    }

    private static func previewMessage(for error: Error) -> AppDisplayText {
        guard let context = CoreErrorRawContextSnapshot(error) else {
            return L10n.display("import.preview.unavailable")
        }

        switch context.kind {
        case .config:
            return L10n.display("import.preview.invalidRules", arguments: [.string(context.rawContext)])
        case .classify:
            return L10n.display("import.preview.category-unavailable", arguments: [.string(context.rawContext)])
        case .permissionDenied:
            return L10n.display("import.preview.pathUnreadable", arguments: [.string(context.rawContext)])
        case .io:
            return L10n.display("import.preview.fileReadFailed", arguments: [.string(context.rawContext)])
        case .db:
            return L10n.display("import.preview.databaseReadFailed", arguments: [.string(context.rawContext)])
        default:
            return L10n.display("import.preview.unavailable")
        }
    }
}
