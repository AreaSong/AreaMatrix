import Combine
import Foundation

@MainActor
final class ImportSingleFilePreviewModel: ObservableObject {
    @Published private(set) var source: ImportSingleFileSource?
    @Published private(set) var prediction: ClassifyResultSnapshot?
    @Published private(set) var status: ImportSingleFilePreviewStatus = .idle
    @Published private(set) var importStatus: ImportSingleFileImportStatus = .idle
    @Published private(set) var preflightStatus: ImportSingleFilePreflightStatus = .idle
    @Published private(set) var isICloudDownloading = false
    @Published var duplicateResolution: ImportSingleFileDuplicateResolutionStrategy = .skip
    @Published var nameConflictResolution: ImportSingleFileNameConflictResolution = .keepBoth
    @Published private(set) var isReplaceConfirmed = false
    @Published private(set) var pendingReplaceConfirmation: ImportSingleFileReplaceConfirmationContext?
    @Published private(set) var replaceConfirmationErrorMessage: String?
    @Published private(set) var replaceConfirmationDiagnosticsMessage: String?
    @Published var selectedCategory = "inbox" {
        didSet { schedulePreflightForCurrentEdits() }
    }
    @Published var suggestedName = "" {
        didSet { schedulePreflightForCurrentEdits() }
    }
    @Published var selectedStorageMode: ImportSingleFileStorageMode = .copy

    private let predictor: any CoreCategoryPredicting
    private let importer: any CoreFileImporting
    private let preflight: any ImportSingleFilePreflighting
    private let placeholderDownloader: any ICloudPlaceholderDownloading
    private let errorMapper: any CoreErrorMapping
    private var request: ImportEntryRequest?
    private var generation = 0
    private var isLoadingRequest = false

    init(
        predictor: any CoreCategoryPredicting,
        importer: any CoreFileImporting,
        preflight: any ImportSingleFilePreflighting = CoreImportSingleFilePreflight(),
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader(),
        errorMapper: any CoreErrorMapping
    ) {
        self.predictor = predictor
        self.importer = importer
        self.preflight = preflight
        self.placeholderDownloader = placeholderDownloader
        self.errorMapper = errorMapper
    }
}

extension ImportSingleFilePreviewModel {
    var importRequest: ImportEntryRequest? {
        request
    }

    var progressRetryContext: ImportProgressRetryContext? {
        guard let request, let sourceURL = request.urls.first else { return nil }
        return ImportProgressRetryContext(
            repoPath: request.repoPath,
            sourcePath: sourceURL.path,
            storageMode: selectedStorageMode,
            overrideCategory: selectedCategory.trimmingCharacters(in: .whitespacesAndNewlines),
            overrideFilename: resolvedImportFilename,
            duplicateStrategy: ImportProgressDuplicateStrategy(coreStrategy: resolvedDuplicateStrategy)
        )
    }
}

extension ImportSingleFilePreviewModel {
    func load(request: ImportEntryRequest) async {
        beginLoading(request: request)
        let currentGeneration = generation
        guard let sourceURL = singleFileSourceURL(from: request) else { return }
        do {
            let result = try await predictor.predictCategory(
                repoPath: request.repoPath,
                filename: sourceURL.lastPathComponent
            )
            guard generation == currentGeneration else { return }
            applyPrediction(result, request: request, fallbackName: sourceURL.lastPathComponent)
            await runPreflightIfReady(generation: currentGeneration)
        } catch {
            guard generation == currentGeneration else { return }
            prediction = nil
            status = .failed(Self.classifyMessage(for: error))
        }
    }

    func retryPreview() async {
        generation += 1
        await runPreflightIfReady(generation: generation)
    }

    func downloadICloudPlaceholderAndRetry() async {
        guard let request, let sourceURL = request.urls.first else { return }
        isICloudDownloading = true
        defer { isICloudDownloading = false }
        do {
            try await placeholderDownloader.downloadPlaceholder(at: sourceURL)
            await retryPreview()
        } catch {
            preflightStatus = .blocked(ImportSingleFilePreflightResult(
                sourceSizeBytes: source?.sizeBytes,
                hashSha256: nil,
                targetRelativePath: ImportSingleFilePreflightTarget.relativePath(
                    category: selectedCategory,
                    filename: suggestedName
                ),
                conflict: .iCloudDownloadFailed(path: sourceURL.path, reason: error.localizedDescription),
                keepBothTargetRelativePath: nil
            ))
        }
    }

    private func schedulePreflightForCurrentEdits() {
        guard !isLoadingRequest else { return }
        guard request != nil, isReadyForImport else { return }
        guard !applyInvalidFilenamePreflightIfNeeded() else { return }
        generation += 1
        let currentGeneration = generation
        resetDuplicateResolutionForPreflight()
        resetNameConflictResolutionForPreflight()
        preflightStatus = .checking("Checking duplicate...")
        Task { await runPreflightIfReady(generation: currentGeneration) }
    }

    @discardableResult
    func importSelectedFile() async -> FileEntrySnapshot? {
        guard let request, let sourceURL = request.urls.first else {
            importStatus = .blocked("没有可导入的单文件来源")
            return nil
        }
        if let existingPath = skippedDuplicateExistingPath {
            importStatus = .skippedDuplicate(existingPath)
            return nil
        }
        if isPendingReplaceConfirmation {
            importStatus = .blocked("Replace 必须先进入二次确认")
            return nil
        }
        if let disabledReason = importDisabledReason {
            importStatus = .blocked(disabledReason)
            return nil
        }

        importStatus = .importing(selectedStorageMode)
        do {
            let entry = try await importFile(
                repoPath: request.repoPath,
                sourceURL: sourceURL,
                overrideCategory: selectedCategory.trimmingCharacters(in: .whitespacesAndNewlines),
                overrideFilename: resolvedImportFilename
            )
            importStatus = .imported(entry)
            return entry
        } catch CoreError.DuplicateFile(let existingPath) {
            applyDuplicateConflict(existingPath: existingPath)
            return nil
        } catch {
            importStatus = .failed(await mapImportError(error))
            return nil
        }
    }
}

private extension ImportSingleFilePreviewModel {
    private func resetForUnsupportedRequest(_ message: String) {
        source = nil
        prediction = nil
        preflightStatus = .idle
        duplicateResolution = .skip
        resetNameConflictResolutionForPreflight()
        resetReplaceStateForPreflight()
        selectedCategory = "inbox"
        suggestedName = ""
        selectedStorageMode = request?.defaultStorageMode ?? .copy
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

    private func runPreflightIfReady(generation currentGeneration: Int) async {
        guard let request, let sourceURL = request.urls.first, isReadyForImport else { return }
        resetDuplicateResolutionForPreflight()
        resetNameConflictResolutionForPreflight()
        resetReplaceStateForPreflight()
        if let invalidFilenamePreflightResult {
            preflightStatus = .blocked(invalidFilenamePreflightResult)
            return
        }
        preflightStatus = .checking("Checking duplicate...")
        let result = await preflight.preflightSingleFileImport(request: ImportSingleFilePreflightRequest(
            repoPath: request.repoPath,
            sourceURL: sourceURL,
            category: selectedCategory,
            targetFilename: suggestedName
        ))
        guard generation == currentGeneration else { return }
        preflightStatus = isImportablePreflightResult(result) ? .ready(result) : .blocked(result)
    }

    private var invalidFilenamePreflightResult: ImportSingleFilePreflightResult? {
        guard let validationMessage = filenameValidationMessage else { return nil }
        return ImportSingleFilePreflightResult(
            sourceSizeBytes: source?.sizeBytes,
            hashSha256: nil,
            targetRelativePath: ImportSingleFilePreflightTarget.relativePath(
                category: selectedCategory,
                filename: suggestedName
            ),
            conflict: .invalidFilename(validationMessage),
            keepBothTargetRelativePath: nil
        )
    }

    private func isImportablePreflightResult(_ result: ImportSingleFilePreflightResult) -> Bool {
        switch result.conflict {
        case .none, .duplicate, .name:
            return true
        case .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return false
        }
    }

    private func importFile(
        repoPath: String,
        sourceURL: URL,
        overrideCategory: String,
        overrideFilename: String
    ) async throws -> FileEntrySnapshot {
        let duplicateStrategy = resolvedDuplicateStrategy
        switch selectedStorageMode {
        case .copy:
            return try await importer.importCopiedFile(
                repoPath: repoPath,
                sourceURL: sourceURL,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        case .move:
            return try await importer.importMovedFile(
                repoPath: repoPath,
                sourceURL: sourceURL,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
            )
        case .indexOnly:
            return try await importer.importIndexedFile(
                repoPath: repoPath,
                sourceURL: sourceURL,
                overrideCategory: overrideCategory,
                overrideFilename: overrideFilename,
                duplicateStrategy: duplicateStrategy
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

    private func beginLoading(request: ImportEntryRequest) {
        isLoadingRequest = true
        defer { isLoadingRequest = false }
        generation += 1
        self.request = request
        importStatus = .idle
        guard let sourceURL = singleFileSourceURL(from: request) else { return }
        resetForNewSingleFileRequest(request, sourceURL: sourceURL)
    }

    private func singleFileSourceURL(from request: ImportEntryRequest) -> URL? {
        guard request.kind == .singleFile, request.urls.count == 1, let sourceURL = request.urls.first else {
            resetForUnsupportedRequest("此 sheet 只处理单文件导入")
            return nil
        }
        return sourceURL
    }

    private func resetForNewSingleFileRequest(_ request: ImportEntryRequest, sourceURL: URL) {
        source = ImportSingleFileSource(url: sourceURL)
        prediction = nil
        preflightStatus = .idle
        status = .loading
        isICloudDownloading = false
        resetDuplicateResolutionForPreflight()
        resetNameConflictResolutionForPreflight()
        resetReplaceStateForPreflight()
        selectedStorageMode = request.defaultStorageMode
        selectedCategory = request.explicitCategory ?? "inbox"
        suggestedName = sourceURL.lastPathComponent
    }
    private func resetDuplicateResolutionForPreflight() {
        duplicateResolution = .skip
    }

    private func applyInvalidFilenamePreflightIfNeeded() -> Bool {
        guard let invalidFilenamePreflightResult else { return false }
        generation += 1
        resetDuplicateResolutionForPreflight()
        resetNameConflictResolutionForPreflight()
        resetReplaceStateForPreflight()
        preflightStatus = .blocked(invalidFilenamePreflightResult)
        return true
    }

    private func applyDuplicateConflict(existingPath: String) {
        let targetRelativePath = ImportSingleFilePreflightTarget.relativePath(
            category: selectedCategory,
            filename: suggestedName
        )
        duplicateResolution = .skip
        resetNameConflictResolutionForPreflight()
        resetReplaceStateForPreflight()
        importStatus = .idle
        preflightStatus = .blocked(ImportSingleFilePreflightResult(
            sourceSizeBytes: source?.sizeBytes,
            hashSha256: currentPreflightResult?.hashSha256,
            targetRelativePath: targetRelativePath,
            conflict: .duplicate(existingPath: existingPath),
            keepBothTargetRelativePath: currentPreflightResult?.keepBothTargetRelativePath
        ))
    }
}

extension ImportSingleFilePreviewModel {
    func blockImportForDuplicateResolution(_ message: String) {
        importStatus = .blocked(message)
    }

    func setPendingReplaceConfirmation(_ context: ImportSingleFileReplaceConfirmationContext?) {
        pendingReplaceConfirmation = context
    }

    func setReplaceConfirmationFailure(_ message: String) {
        replaceConfirmationErrorMessage = message
        replaceConfirmationDiagnosticsMessage = nil
    }

    func collectReplaceConfirmationDiagnostics() {
        replaceConfirmationDiagnosticsMessage = [
            "Diagnostics collected for replace confirmation state.",
            "No user file contents included.",
        ].joined(separator: " ")
    }

    func clearReplaceConfirmationRecovery() {
        replaceConfirmationErrorMessage = nil
        replaceConfirmationDiagnosticsMessage = nil
    }

    func markReplaceConfirmed(_ isConfirmed: Bool) {
        isReplaceConfirmed = isConfirmed
    }

    func resetReplaceStateForPreflight() {
        isReplaceConfirmed = false
        pendingReplaceConfirmation = nil
        clearReplaceConfirmationRecovery()
    }

    func setNameConflictResolution(_ resolution: ImportSingleFileNameConflictResolution) {
        nameConflictResolution = resolution
    }

    func resetNameConflictResolutionForPreflight() {
        nameConflictResolution = .keepBoth
    }
}

private extension ImportEntryRequest {
    var explicitCategory: String? {
        guard case .category(let slug) = destination else { return nil }
        return slug
    }
}
