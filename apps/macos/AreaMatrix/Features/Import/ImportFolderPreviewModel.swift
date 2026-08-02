import Combine
import Foundation

@MainActor
final class ImportFolderPreviewModel: ObservableObject {
    @Published private(set) var rows: [ImportFolderPreviewRow] = []
    @Published private(set) var status: ImportFolderPreviewStatus = .idle
    @Published private(set) var folderCount = 0
    @Published private(set) var skippedRules: [ImportFolderSkippedRule] = []
    @Published private(set) var scanErrors: [ImportFolderScanError] = []
    @Published private(set) var isICloudDownloading = false
    @Published private(set) var iCloudDownloadErrorMessage: LocalizedMessage?
    @Published private(set) var replaceConfirmationErrorMessage: LocalizedMessage?
    @Published private(set) var replaceConfirmationDiagnosticsMessage: LocalizedMessage?
    @Published var includeHiddenFiles = false
    @Published var followSymlinks = false
    @Published var selectedDestination: ImportBatchDestinationOption = .autoClassify
    @Published var selectedStorageMode: ImportSingleFileStorageMode = .copy

    private let predictor: any CoreCategoryPredicting
    let importer: any CoreBatchCopyImporting
    let errorMapper: any CoreErrorMapping
    private let conflictPrechecker: any ImportFolderConflictPrechecking
    private let scanner: any ImportFolderScanning
    private let placeholderDownloader: any ICloudPlaceholderDownloading
    var request: ImportEntryRequest?
    private var generation = 0
    private(set) var lastFailureMapping: CoreErrorMappingSnapshot?

    init(
        predictor: any CoreCategoryPredicting,
        importer: any CoreBatchCopyImporting,
        errorMapper: any CoreErrorMapping,
        conflictPrechecker: any ImportFolderConflictPrechecking,
        scanner: any ImportFolderScanning = ImportPlatformServices.folderScanner,
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader()
    ) {
        self.predictor = predictor
        self.importer = importer
        self.errorMapper = errorMapper
        self.conflictPrechecker = conflictPrechecker
        self.scanner = scanner
        self.placeholderDownloader = placeholderDownloader
    }
}

extension ImportFolderPreviewModel {
    var folderURL: URL? {
        request?.urls.first
    }

    var folderPathLabel: String {
        guard let path = folderURL?.path else {
            return L10n.string("import.folder.unknown")
        }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    var destinationOptions: [ImportBatchDestinationOption] {
        var options: [ImportBatchDestinationOption] = [.autoClassify]
        if request?.destination == .repositoryRoot {
            options.append(.repositoryRoot)
        }
        options.append(contentsOf: request?.availableCategories.map(ImportBatchDestinationOption.category) ?? [])
        if let selected = request?.destination.folderDestinationOption, !options.contains(selected) {
            options.append(selected)
        }
        return options.uniqued()
    }

    var totalSizeDescription: String? {
        let total = rows.compactMap(\.sizeBytes).reduce(0, +)
        guard total > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var readyCount: Int {
        rows.filter(\.status.importsIncomingFile).count
    }

    var failedCount: Int {
        rows.filter(\.status.isFailed).count
    }

    var duplicateCount: Int {
        rows.filter { row in
            if case .duplicate = row.status { return true }
            if case .skippedDuplicate = row.status { return true }
            return false
        }.count
    }

    var nameConflictCount: Int {
        rows.filter { row in
            if case .nameConflict = row.status { return true }
            return false
        }.count
    }

    var blockedCount: Int {
        rows.filter(\.isBlockedForImport).count
    }

    var replaceOptionVisibility: ImportSingleFileReplaceOptionVisibility {
        guard request?.allowReplaceDuringImport == true else { return .hidden }
        return request?.isTrashAvailable == true ? .enabled : .disabled
    }

    func retryReplaceConfirmation() {
        clearReplaceConfirmationRecovery()
    }

    func collectReplaceConfirmationDiagnostics() {
        replaceConfirmationDiagnosticsMessage = L10n.message("import.replace-confirmation.diagnostics-collected")
    }

    func clearReplaceConfirmationRecovery() {
        replaceConfirmationErrorMessage = nil
        replaceConfirmationDiagnosticsMessage = nil
    }

    func recordReplaceConfirmationFailure(_ message: LocalizedMessage) {
        replaceConfirmationErrorMessage = message
        replaceConfirmationDiagnosticsMessage = nil
    }

    var iCloudPlaceholderCount: Int {
        rows.filter { row in
            if case .iCloudPlaceholder = row.status { return true }
            return false
        }.count
    }

    var importableRows: [ImportFolderPreviewRow] {
        rows.filter(\.status.importsIncomingFile)
    }

    var currentImportPath: String? {
        rows.first(where: { $0.status.isImporting }).map { targetRelativePath(for: $0) }
            ?? importableRows.first.map { targetRelativePath(for: $0) }
    }

    var importDisabledReason: String? {
        if status.isScanning {
            return L10n.string("预扫描完成前不能导入")
        }
        if isICloudDownloading {
            return L10n.string("正在下载 iCloud 文件")
        }
        if rows.contains(where: \.status.isImporting) {
            return selectedStorageMode.importingBlockingMessage
        }
        if !scanErrors.isEmpty {
            return L10n.string("预扫描存在错误，请先 Retry scan 或 Cancel")
        }
        if blockedCount > 0 {
            return L10n.string("存在 BLOCKED 项，请先完成冲突处理")
        }
        if rows.isEmpty || importableRows.isEmpty {
            return L10n.string("没有可导入文件")
        }
        return nil
    }

    var storageModeRiskMessage: String? {
        switch selectedStorageMode {
        case .copy:
            nil
        case .move:
            L10n.string("Move 模式会移走源文件夹中的已就绪文件；请确认这些文件要移入资料库。")
        case .indexOnly:
            L10n.string("Index-only 不复制文件，只写入索引；源文件移动或删除后会显示缺失。")
        }
    }

    func load(request: ImportEntryRequest) async {
        generation += 1
        let currentGeneration = generation
        let isNewRequest = self.request?.id != request.id
        self.request = request
        if isNewRequest {
            selectedStorageMode = request.defaultStorageMode
            selectedDestination = request.destination.folderDestinationOption
        }

        guard case .folder = request.kind, let rootURL = request.urls.first else {
            reset(message: L10n.display("import.folder.unsupportedRequest"))
            return
        }

        status = .scanning(path: (rootURL.path as NSString).abbreviatingWithTildeInPath)
        rows = []
        folderCount = 0
        skippedRules = []
        scanErrors = []
        iCloudDownloadErrorMessage = nil
        clearReplaceConfirmationRecovery()
        lastFailureMapping = nil

        let result = await scanner.scanFolder(
            rootURL: rootURL,
            includeHiddenFiles: includeHiddenFiles,
            followSymlinks: followSymlinks
        )
        guard generation == currentGeneration else { return }

        rows = result.rows
        folderCount = result.folderCount
        skippedRules = result.skippedRules
        scanErrors = result.errors

        guard !rows.isEmpty else {
            status = result.errors.isEmpty
                ? .empty
                : .failed(L10n.display(
                    "import.folder.prescanFailed",
                    technicalDetail: result.errors.first?.message
                ))
            return
        }

        await classifyRows(repoPath: request.repoPath, generation: currentGeneration)
    }

    func retryScan() async {
        guard let request else { return }
        await load(request: request)
    }

    func downloadICloudPlaceholdersAndRetry() async -> Bool {
        let placeholderURLs = rows.compactMap { row -> URL? in
            if case .iCloudPlaceholder = row.status {
                return row.fileURL
            }
            return nil
        }
        guard !placeholderURLs.isEmpty else { return false }

        isICloudDownloading = true
        iCloudDownloadErrorMessage = nil
        defer { isICloudDownloading = false }

        var failures: [String] = []
        for url in placeholderURLs {
            do {
                try await placeholderDownloader.downloadPlaceholder(at: url)
            } catch {
                failures.append(
                    L10n.format("import.folder.scan-item-error", url.lastPathComponent, error.localizedDescription)
                )
            }
        }

        guard failures.isEmpty else {
            iCloudDownloadErrorMessage = L10n.message(
                "import.icloud.downloadFailed",
                arguments: [.integer(failures.count), .string(failures[0])],
                technicalDetail: failures.joined(separator: "\n")
            )
            return false
        }

        await retryScan()
        return true
    }

    func updateIncludeHiddenFiles(_ value: Bool) {
        includeHiddenFiles = value
        Task { await retryScan() }
    }

    func updateFollowSymlinks(_ value: Bool) {
        followSymlinks = value
        Task { await retryScan() }
    }

    private func classifyRows(repoPath: String, generation currentGeneration: Int) async {
        for index in rows.indices {
            let row = rows[index]
            if case .iCloudPlaceholder = row.status { continue }
            do {
                let prediction = try await predictor.predictCategory(
                    repoPath: repoPath,
                    filename: row.originalName
                )
                guard generation == currentGeneration else { return }
                rows[index] = row.withPrediction(prediction)
            } catch {
                guard generation == currentGeneration else { return }
                rows[index] = row.withStatus(.error(Self.previewMessage(for: error)))
            }
        }

        guard generation == currentGeneration else { return }
        await precheckConflicts(repoPath: repoPath, generation: currentGeneration)
        guard generation == currentGeneration else { return }
        status = .loaded(ready: readyCount, total: rows.count, failed: failedCount)
    }

    private func precheckConflicts(repoPath: String, generation currentGeneration: Int) async {
        status = .checkingConflicts
        let results = await conflictPrechecker.precheckFolderConflicts(
            repoPath: repoPath,
            rows: rows,
            destination: selectedDestination
        )
        guard generation == currentGeneration else { return }
        guard !results.isEmpty else { return }

        rows = rows.map { row in
            guard let result = results[row.id] else { return row }
            return row.withConflictPrecheck(result)
        }
    }

    private func reset(message: AppDisplayText) {
        rows = []
        folderCount = 0
        skippedRules = []
        scanErrors = []
        lastFailureMapping = nil
        selectedStorageMode = request?.defaultStorageMode ?? .copy
        status = .failed(message)
    }

    func clearLastFailureMapping() {
        lastFailureMapping = nil
    }

    func recordLastFailureMapping(_ mapping: CoreErrorMappingSnapshot) {
        lastFailureMapping = mapping
    }

    func updateRowStatus(at index: Int, status: ImportFolderPreviewRowStatus) {
        guard rows.indices.contains(index) else { return }
        rows[index].status = status
    }

    func updateRowCommitState(at index: Int, commitState: CoreImportCommitState) {
        guard rows.indices.contains(index) else { return }
        rows[index].importCommitState = commitState
    }

    func setRowStatus(_ status: ImportFolderPreviewRowStatus, for rowID: ImportFolderPreviewRow.ID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].status = status
    }

    private static func previewMessage(for error: Error) -> AppDisplayText {
        guard let context = CoreErrorRawContextSnapshot(error) else {
            return L10n.display("import.preview.unavailable", technicalDetail: error.localizedDescription)
        }

        switch context.kind {
        case .config:
            return L10n.display(
                "import.preview.invalidRules",
                arguments: [.string(context.rawContext)],
                technicalDetail: context.rawContext
            )
        case .classify:
            return L10n.display(
                "import.preview.category-unavailable",
                arguments: [.string(context.rawContext)],
                technicalDetail: context.rawContext
            )
        case .permissionDenied:
            return L10n.display(
                "import.preview.pathUnreadable",
                arguments: [.string(context.rawContext)],
                technicalDetail: context.rawContext
            )
        case .io:
            return L10n.display(
                "import.preview.fileReadFailed",
                arguments: [.string(context.rawContext)],
                technicalDetail: context.rawContext
            )
        default:
            return L10n.display("import.preview.unavailable", technicalDetail: context.rawContext)
        }
    }

    func targetRelativePath(for row: ImportFolderPreviewRow) -> String {
        let filename = row.resolvedIncomingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedDestination == .repositoryRoot {
            return filename
        }
        let category = targetCategory(for: row)
        guard let category, !category.isEmpty else {
            return filename
        }
        return "\(category)/\(filename)"
    }

    private func targetCategory(for row: ImportFolderPreviewRow) -> String? {
        switch selectedDestination {
        case .autoClassify:
            row.predictedCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .category(slug):
            slug.trimmingCharacters(in: .whitespacesAndNewlines)
        case .repositoryRoot:
            nil
        }
    }
}

private extension ImportFolderPreviewRow {
    func withConflictPrecheck(_ result: ImportFolderConflictPrecheckResult) -> ImportFolderPreviewRow {
        switch result {
        case let .duplicate(existingPath):
            withStatus(.duplicate(existingPath: existingPath, strategy: .skip, isReplaceConfirmed: false))
        case let .nameConflict(existingPath):
            withStatus(.nameConflict(existingPath: existingPath, resolution: .keepBoth))
        case let .blocked(message):
            withStatus(.blocked(message))
        }
    }
}

private extension ImportEntryDestination {
    var folderDestinationOption: ImportBatchDestinationOption {
        switch self {
        case .autoClassify:
            .autoClassify
        case let .category(slug):
            .category(slug)
        case .repositoryRoot:
            .repositoryRoot
        }
    }
}
