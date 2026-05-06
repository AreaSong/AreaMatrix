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
    case importing(ImportSingleFileStorageMode)
    case imported(ImportSingleFileStorageMode)
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
        case .importing(let mode):
            return mode.importingMessage
        case .imported(let mode):
            return mode.folderImportedMessage
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
    @Published var selectedStorageMode: ImportSingleFileStorageMode = .copy

    private let predictor: any CoreCategoryPredicting
    let importer: any CoreBatchCopyImporting
    let errorMapper: any CoreErrorMapping
    private let scanner: any ImportFolderScanning
    var request: ImportEntryRequest?
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
            return selectedStorageMode.importingBlockingMessage
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
}

private extension ImportSingleFileStorageMode {
    var folderImportedMessage: String {
        switch self {
        case .copy:
            return "已复制导入"
        case .move:
            return "已移动导入"
        case .indexOnly:
            return "已写入索引"
        }
    }
}
