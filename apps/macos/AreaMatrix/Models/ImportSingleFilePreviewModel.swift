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
    @Published private(set) var isReplaceConfirmed = false
    @Published private(set) var pendingReplaceConfirmation: ImportSingleFileReplaceConfirmationContext?
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
    private var allowReplaceDuringImport = false
    private var isTrashAvailable = true

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
    var reasonSummary: String {
        guard let prediction else { return "暂无分类解释" }
        return "\(prediction.reason.displayLabel) · \(prediction.confidencePercent)%"
    }

    var sourceSizeDescription: String? {
        let sizeBytes = source?.sizeBytes ?? currentPreflightResult?.sourceSizeBytes
        guard let sizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var filenameValidationMessage: String? {
        ImportSingleFileFilenameValidator.validationMessage(for: suggestedName)
    }

    var preflightMessage: String? {
        if isICloudDownloading {
            return "正在下载 iCloud 文件..."
        }
        return preflightStatus.message
    }

    var currentPreflightResult: ImportSingleFilePreflightResult? {
        switch preflightStatus {
        case .ready(let result), .blocked(let result):
            return result
        case .idle, .checking:
            return nil
        }
    }

    var progressCurrentPath: String {
        if let currentPreflightResult {
            return currentPreflightResult.targetRelativePath
        }
        return ImportSingleFilePreflightTarget.relativePath(
            category: selectedCategory,
            filename: suggestedName
        )
    }

    var progressRetryContext: ImportProgressRetryContext? {
        guard let request, let sourceURL = request.urls.first else { return nil }
        return ImportProgressRetryContext(
            repoPath: request.repoPath,
            sourcePath: sourceURL.path,
            storageMode: selectedStorageMode,
            overrideCategory: selectedCategory.trimmingCharacters(in: .whitespacesAndNewlines),
            overrideFilename: suggestedName.trimmingCharacters(in: .whitespacesAndNewlines),
            duplicateStrategy: ImportProgressDuplicateStrategy(coreStrategy: resolvedDuplicateStrategy)
        )
    }

    var showsICloudActions: Bool {
        guard let result = currentPreflightResult else { return false }
        switch result.conflict {
        case .iCloudPlaceholder, .iCloudDownloadFailed:
            return true
        case .none, .invalidFilename, .name, .duplicate, .corePreviewUnavailable, .sourceUnavailable, .error:
            return false
        }
    }

    var showsRetryPreviewAction: Bool {
        guard let result = currentPreflightResult else { return false }
        switch result.conflict {
        case .sourceUnavailable, .error:
            return true
        case .none, .invalidFilename, .name, .duplicate, .iCloudPlaceholder, .iCloudDownloadFailed,
             .corePreviewUnavailable:
            return false
        }
    }

    var showsConflictSection: Bool {
        guard let result = currentPreflightResult else { return false }
        switch result.conflict {
        case .none, .name, .duplicate:
            return true
        case .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return false
        }
    }

    var activeConflictPage: ImportSingleFileConflictPage? {
        guard let result = currentPreflightResult else { return nil }
        return ImportSingleFileConflictPage(conflict: result.conflict)
    }

    var importFailureMapping: CoreErrorMappingSnapshot? {
        guard case .failed(let mapping) = importStatus else { return nil }
        return mapping
    }

    var importDisabledReason: String? {
        if importStatus.isImporting {
            return importStatus.blockingMessage ?? "正在导入"
        }
        if importStatus.isImported {
            return "文件已导入"
        }
        if !isReadyForImport {
            return status.message ?? "导入预检未完成"
        }
        if selectedCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请选择导入分类"
        }
        if let filenameValidationMessage {
            return filenameValidationMessage
        }
        if let preflightBlocker = preflightStatus.importBlockingReason(isReplaceConfirmed: isReplaceConfirmed) {
            return preflightBlocker
        }
        return nil
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
                replaceOptionVisibility: .hidden
            ))
        }
    }

    func beginReplaceConfirmation() {
        guard let request, let sourceURL = request.urls.first else { return }
        pendingReplaceConfirmation = currentPreflightResult?.replaceConfirmationContext(
            incomingPath: sourceURL.path
        )
    }

    func cancelReplaceConfirmation() {
        pendingReplaceConfirmation = nil
    }

    func applyReplaceConfirmation(_ decision: ImportSingleFileReplaceConfirmationDecision) {
        guard pendingReplaceConfirmation == decision.context else {
            importStatus = .blocked("Replace confirmation context expired")
            pendingReplaceConfirmation = nil
            isReplaceConfirmed = false
            return
        }
        guard decision.understandsReplace else {
            importStatus = .blocked("Replace 需要先勾选二次确认")
            isReplaceConfirmed = false
            return
        }
        pendingReplaceConfirmation = nil
        isReplaceConfirmed = true
    }

    private func schedulePreflightForCurrentEdits() {
        guard !isLoadingRequest else { return }
        guard request != nil, isReadyForImport else { return }
        guard !applyInvalidFilenamePreflightIfNeeded() else { return }
        generation += 1
        let currentGeneration = generation
        resetReplaceStateForPreflight()
        preflightStatus = .checking("正在检查 preview/hash/conflict precheck")
        Task { await runPreflightIfReady(generation: currentGeneration) }
    }

    @discardableResult
    func importSelectedFile() async -> FileEntrySnapshot? {
        guard let request, let sourceURL = request.urls.first else {
            importStatus = .blocked("没有可导入的单文件来源")
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
                overrideFilename: suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            importStatus = .imported(entry)
            return entry
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
        isReplaceConfirmed = false
        pendingReplaceConfirmation = nil
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

    private func runPreflightIfReady(generation currentGeneration: Int) async {
        guard let request, let sourceURL = request.urls.first, isReadyForImport else { return }
        resetReplaceStateForPreflight()
        if let invalidFilenamePreflightResult {
            preflightStatus = .blocked(invalidFilenamePreflightResult)
            return
        }
        preflightStatus = .checking("正在检查 preview/hash/conflict precheck")
        let result = await preflight.preflightSingleFileImport(request: ImportSingleFilePreflightRequest(
            repoPath: request.repoPath,
            sourceURL: sourceURL,
            category: selectedCategory,
            targetFilename: suggestedName,
            allowReplaceDuringImport: allowReplaceDuringImport,
            isTrashAvailable: isTrashAvailable
        ))
        guard generation == currentGeneration else { return }
        preflightStatus = result.importBlockingReason(isReplaceConfirmed: false) == nil ? .ready(result) : .blocked(result)
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
            replaceOptionVisibility: .hidden
        )
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

    private var resolvedDuplicateStrategy: DuplicateStrategy {
        isReplaceConfirmed ? .overwrite : .ask
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
        resetReplaceStateForPreflight()
        selectedStorageMode = .copy
        allowReplaceDuringImport = request.allowReplaceDuringImport
        isTrashAvailable = request.isTrashAvailable
        selectedCategory = request.explicitCategory ?? "inbox"
        suggestedName = sourceURL.lastPathComponent
    }
    private func resetReplaceStateForPreflight() {
        isReplaceConfirmed = false
        pendingReplaceConfirmation = nil
    }

    private func applyInvalidFilenamePreflightIfNeeded() -> Bool {
        guard let invalidFilenamePreflightResult else { return false }
        generation += 1
        resetReplaceStateForPreflight()
        preflightStatus = .blocked(invalidFilenamePreflightResult)
        return true
    }
}

private extension ImportSingleFileImportStatus {
    var isImported: Bool {
        if case .imported = self { return true }
        return false
    }

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
