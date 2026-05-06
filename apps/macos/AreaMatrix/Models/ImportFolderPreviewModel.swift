import Combine
import Foundation

protocol ImportFolderScanning: Sendable {
    func scanFolder(rootURL: URL, includeHiddenFiles: Bool, followSymlinks: Bool) async -> ImportFolderScanResult
}

struct ImportFolderScanResult: Equatable, Sendable {
    var rows: [ImportFolderPreviewRow]
    var folderCount: Int
    var skippedRules: [ImportFolderSkippedRule]
    var errors: [ImportFolderScanError]
}

struct ImportFolderSkippedRule: Equatable, Sendable, Identifiable {
    var label: String
    var count: Int

    var id: String { label }
}

struct ImportFolderScanError: Equatable, Sendable, Identifiable {
    var path: String
    var message: String

    var id: String { "\(path)::\(message)" }
}

enum ImportFolderPreviewStatus: Equatable, Sendable {
    case idle
    case scanning(path: String)
    case loaded(ready: Int, total: Int, failed: Int)
    case empty
    case failed(String)

    var isScanning: Bool {
        if case .scanning = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .scanning(let path):
            return "正在预扫描 \(path)"
        case .loaded(let ready, let total, let failed):
            if failed == 0 {
                return "已完成 \(total) 个文件的分类预览"
            }
            return "已完成 \(ready)/\(total) 个文件的分类预览，\(failed) 个失败"
        case .empty:
            return "没有可导入文件"
        case .failed(let message):
            return message
        }
    }
}

enum ImportFolderPreviewRowStatus: Equatable, Sendable {
    case loading
    case ready(reasonLabel: String)
    case iCloudPlaceholder(path: String)
    case importing
    case imported
    case error(String)

    var tag: String {
        switch self {
        case .loading:
            return "PREVIEW"
        case .ready:
            return "OK"
        case .iCloudPlaceholder:
            return "ICLOUD"
        case .importing:
            return "IMPORTING"
        case .imported:
            return "IMPORTED"
        case .error:
            return "ERROR"
        }
    }

    var detail: String? {
        switch self {
        case .loading:
            return "Preparing preview..."
        case .ready(let reasonLabel):
            return reasonLabel
        case .iCloudPlaceholder(let path):
            return "iCloud placeholder 需要下载后才能导入：\(path)"
        case .importing:
            return "正在复制导入..."
        case .imported:
            return "已复制导入"
        case .error(let message):
            return message
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .error = self { return true }
        return false
    }

    var isImporting: Bool {
        if case .importing = self { return true }
        return false
    }
}

struct ImportFolderPreviewRow: Identifiable, Equatable, Sendable {
    var fileURL: URL
    var rootURL: URL
    var originalName: String
    var relativePath: String
    var sizeBytes: Int64?
    var predictedCategory: String?
    var suggestedName: String
    var status: ImportFolderPreviewRowStatus

    var id: String { fileURL.path }

    static func loading(fileURL: URL, rootURL: URL) -> ImportFolderPreviewRow {
        ImportFolderPreviewRow(
            fileURL: fileURL,
            rootURL: rootURL,
            originalName: fileURL.lastPathComponent,
            relativePath: relativePath(for: fileURL, rootURL: rootURL),
            sizeBytes: Self.sizeBytes(for: fileURL),
            predictedCategory: nil,
            suggestedName: fileURL.lastPathComponent,
            status: .loading
        )
    }

    func withPrediction(_ prediction: ClassifyResultSnapshot) -> ImportFolderPreviewRow {
        var row = self
        row.predictedCategory = prediction.category
        row.suggestedName = prediction.suggestedName.isEmpty ? originalName : prediction.suggestedName
        row.status = .ready(reasonLabel: "\(prediction.reason.displayLabel) · \(prediction.confidencePercent)%")
        return row
    }

    func withStatus(_ status: ImportFolderPreviewRowStatus) -> ImportFolderPreviewRow {
        var row = self
        row.status = status
        return row
    }

    private static func sizeBytes(for url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    private static func relativePath(for fileURL: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else {
            return fileURL.lastPathComponent
        }

        let startIndex = filePath.index(filePath.startIndex, offsetBy: rootPath.count)
        let relative = filePath[startIndex...].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? fileURL.lastPathComponent : relative
    }
}

@MainActor
final class ImportFolderPreviewModel: ObservableObject {
    @Published private(set) var rows: [ImportFolderPreviewRow] = []
    @Published private(set) var status: ImportFolderPreviewStatus = .idle
    @Published private(set) var folderCount = 0
    @Published private(set) var skippedRules: [ImportFolderSkippedRule] = []
    @Published private(set) var scanErrors: [ImportFolderScanError] = []
    @Published var includeHiddenFiles = false
    @Published var followSymlinks = false

    private let predictor: any CoreCategoryPredicting
    private let importer: any CoreBatchCopyImporting
    private let errorMapper: any CoreErrorMapping
    private let scanner: any ImportFolderScanning
    private var request: ImportEntryRequest?
    private var generation = 0
    private(set) var lastFailureMapping: CoreErrorMappingSnapshot?

    init(
        predictor: any CoreCategoryPredicting,
        importer: any CoreBatchCopyImporting,
        errorMapper: any CoreErrorMapping,
        scanner: any ImportFolderScanning = LocalImportFolderScanner()
    ) {
        self.predictor = predictor
        self.importer = importer
        self.errorMapper = errorMapper
        self.scanner = scanner
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

    var totalSizeDescription: String? {
        let total = rows.compactMap(\.sizeBytes).reduce(0, +)
        guard total > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    var readyCount: Int {
        rows.filter(\.status.isReady).count
    }

    var failedCount: Int {
        rows.filter(\.status.isFailed).count
    }

    var iCloudPlaceholderCount: Int {
        rows.filter { row in
            if case .iCloudPlaceholder = row.status { return true }
            return false
        }.count
    }

    var importableRows: [ImportFolderPreviewRow] {
        rows.filter(\.status.isReady)
    }

    var currentImportPath: String? {
        rows.first(where: { $0.status.isImporting }).map { targetRelativePath(for: $0) }
            ?? importableRows.first.map { targetRelativePath(for: $0) }
    }

    var importDisabledReason: String? {
        if status.isScanning {
            return "预扫描完成前不能导入"
        }
        if rows.contains(where: { $0.status.isImporting }) {
            return "正在复制导入"
        }
        if rows.isEmpty || importableRows.isEmpty {
            return "没有可导入文件"
        }
        return nil
    }

    func load(request: ImportEntryRequest) async {
        generation += 1
        let currentGeneration = generation
        self.request = request

        guard case .folder = request.kind, let rootURL = request.urls.first else {
            reset(message: "此 sheet 只处理文件夹递归导入")
            return
        }

        status = .scanning(path: (rootURL.path as NSString).abbreviatingWithTildeInPath)
        rows = []
        folderCount = 0
        skippedRules = []
        scanErrors = []
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
        status = .loaded(ready: readyCount, total: rows.count, failed: failedCount)
    }

    private func reset(message: String) {
        rows = []
        folderCount = 0
        skippedRules = []
        scanErrors = []
        lastFailureMapping = nil
        status = .failed(message)
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

@MainActor
extension ImportFolderPreviewModel {
    func importReadyFiles(
        reportProgress: @escaping @MainActor (ImportBatchProgressSnapshot) -> Void = { _ in }
    ) async -> ImportBatchImportResult? {
        guard let request, importDisabledReason == nil else { return nil }

        let readyRowIDs = Set(importableRows.map(\.id))
        let total = importableRows.count
        let initialPreviewErrorCount = failedCount
        var completed = 0
        var failed = 0
        var succeededEntries: [FileEntrySnapshot] = []
        var lastImportedPath = ""
        lastFailureMapping = nil

        for index in rows.indices where readyRowIDs.contains(rows[index].id) {
            let cycle = await runFolderCopyCycle(
                at: index,
                request: request,
                completed: completed,
                failed: failed,
                total: total
            )
            completed = cycle.completed
            failed = cycle.failed
            lastImportedPath = cycle.lastImportedPath ?? lastImportedPath
            if let entry = cycle.entry {
                succeededEntries.append(entry)
            }
            reportProgress(cycle.progress)
        }

        return ImportBatchImportResult(
            succeededEntries: succeededEntries,
            failedCount: failed,
            previewErrorCount: initialPreviewErrorCount,
            total: total,
            lastImportedPath: lastImportedPath,
            pendingDuplicateCount: 0,
            skippedDuplicateCount: 0,
            pendingICloudCount: iCloudPlaceholderCount
        )
    }

    func targetRelativePath(for row: ImportFolderPreviewRow) -> String {
        let filename = row.suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if request?.destination == .repositoryRoot {
            return filename
        }
        let category = row.predictedCategory?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let category, !category.isEmpty else {
            return filename
        }
        return "\(category)/\(filename)"
    }

    private func runFolderCopyCycle(
        at rowIndex: Int,
        request: ImportEntryRequest,
        completed: Int,
        failed: Int,
        total: Int
    ) async -> ImportBatchCopyCycleResult {
        let row = rows[rowIndex]
        let currentPath = targetRelativePath(for: row)
        rows[rowIndex].status = .importing

        do {
            let entry = try await importer.importCopiedFile(
                repoPath: request.repoPath,
                sourceURL: row.fileURL,
                destination: request.destination,
                suggestedCategory: suggestedCategory(for: row, request: request),
                overrideFilename: row.suggestedName,
                duplicateStrategy: .ask
            )
            rows[rowIndex].status = .imported
            return .success(
                entry: entry,
                completed: completed + 1,
                failed: failed,
                total: total,
                currentPath: currentPath
            )
        } catch {
            let mapping = await mapImportError(error)
            lastFailureMapping = mapping
            rows[rowIndex].status = .error(mapping.userMessage)
            return .failure(
                completed: completed,
                failed: failed + 1,
                total: total,
                currentPath: currentPath
            )
        }
    }

    private func mapImportError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }
        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }

    private func suggestedCategory(for row: ImportFolderPreviewRow, request: ImportEntryRequest) -> String? {
        switch request.destination {
        case .autoClassify:
            return row.predictedCategory
        case .category(let slug):
            return slug
        case .repositoryRoot:
            return nil
        }
    }
}
