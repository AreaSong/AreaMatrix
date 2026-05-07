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
    @Published private(set) var iCloudDownloadErrorMessage: String?
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
        conflictPrechecker: any ImportFolderConflictPrechecking = CoreImportFolderConflictPrechecker(),
        scanner: any ImportFolderScanning = LocalImportFolderScanner(),
        placeholderDownloader: any ICloudPlaceholderDownloading = LocalICloudPlaceholderDownloader()
    ) {
        self.predictor = predictor
        self.importer = importer
        self.errorMapper = errorMapper
        self.conflictPrechecker = conflictPrechecker
        self.scanner = scanner
        self.placeholderDownloader = placeholderDownloader
    }

    var folderURL: URL? {
        request?.urls.first
    }

    var folderPathLabel: String {
        guard let path = folderURL?.path else {
            return "未知文件夹"
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
            return "预扫描完成前不能导入"
        }
        if isICloudDownloading {
            return "正在下载 iCloud 文件"
        }
        if rows.contains(where: { $0.status.isImporting }) {
            return selectedStorageMode.importingBlockingMessage
        }
        if !scanErrors.isEmpty {
            return "预扫描存在错误，请先 Retry scan 或 Cancel"
        }
        if blockedCount > 0 {
            return "存在 BLOCKED 项，请先完成冲突处理"
        }
        if rows.isEmpty || importableRows.isEmpty {
            return "没有可导入文件"
        }
        if selectedStorageMode == .move {
            return "文件夹导入当前只接入 Copy / Index-only；Move 属于 C1-07 后续能力"
        }
        return nil
    }

    var storageModeRiskMessage: String? {
        switch selectedStorageMode {
        case .copy:
            return nil
        case .move:
            return "Move 模式会移走源文件；S1-19 当前不执行真实 Move 导入。"
        case .indexOnly:
            return "Index-only 不复制文件，只写入索引；源文件移动或删除后会显示缺失。"
        }
    }

    func load(request: ImportEntryRequest) async {
        generation += 1
        let currentGeneration = generation
        let isNewRequest = self.request?.id != request.id
        self.request = request
        if isNewRequest {
            selectedStorageMode = .copy
            selectedDestination = request.destination.folderDestinationOption
        }

        guard case .folder = request.kind, let rootURL = request.urls.first else {
            reset(message: "此 sheet 只处理文件夹递归导入")
            return
        }

        status = .scanning(path: (rootURL.path as NSString).abbreviatingWithTildeInPath)
        rows = []
        folderCount = 0
        skippedRules = []
        scanErrors = []
        iCloudDownloadErrorMessage = nil
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
            status = result.errors.isEmpty ? .empty : .failed(result.errors.first?.message ?? "预扫描失败")
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
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        guard failures.isEmpty else {
            iCloudDownloadErrorMessage = "iCloud 下载失败：\(failures.count) 个，\(failures[0])"
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

    private func reset(message: String) {
        rows = []
        folderCount = 0
        skippedRules = []
        scanErrors = []
        lastFailureMapping = nil
        selectedStorageMode = .copy
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

    func setRowStatus(_ status: ImportFolderPreviewRowStatus, for rowID: ImportFolderPreviewRow.ID) {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return }
        rows[index].status = status
    }

    private static func previewMessage(for error: Error) -> String {
        guard let coreError = error as? CoreError else {
            return "无法完成分类预览"
        }

        switch coreError {
        case .Config(let reason):
            return "分类规则无效：\(reason)"
        case .Classify(let reason):
            return "无法预览分类：\(reason)"
        case .PermissionDenied(let path):
            return "无法读取分类预览路径：\(path)"
        case .Io(let message):
            return "分类预览文件读取失败：\(message)"
        default:
            return "无法完成分类预览"
        }
    }
}

extension ImportFolderPreviewModel {
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
            return row.predictedCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        case .category(let slug):
            return slug.trimmingCharacters(in: .whitespacesAndNewlines)
        case .repositoryRoot:
            return nil
        }
    }
}

private extension ImportFolderPreviewRow {
    func withConflictPrecheck(_ result: ImportFolderConflictPrecheckResult) -> ImportFolderPreviewRow {
        switch result {
        case .duplicate(let existingPath):
            return withStatus(.duplicate(existingPath: existingPath, strategy: .skip, isReplaceConfirmed: false))
        case .nameConflict(let existingPath):
            return withStatus(.nameConflict(existingPath: existingPath, resolution: .keepBoth))
        case .blocked(let message):
            return withStatus(.blocked(message))
        }
    }
}

private extension ImportEntryDestination {
    var folderDestinationOption: ImportBatchDestinationOption {
        switch self {
        case .autoClassify:
            return .autoClassify
        case .category(let slug):
            return .category(slug)
        case .repositoryRoot:
            return .repositoryRoot
        }
    }
}

private extension Array where Element == ImportBatchDestinationOption {
    func uniqued() -> [ImportBatchDestinationOption] {
        var seen = Set<ImportBatchDestinationOption>()
        return filter { seen.insert($0).inserted }
    }
}
