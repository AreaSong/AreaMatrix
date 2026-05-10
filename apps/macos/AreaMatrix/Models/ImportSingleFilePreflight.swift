import Foundation

protocol ImportSingleFilePreflighting: Sendable {
    func preflightSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult
}

protocol ICloudPlaceholderDownloading: Sendable {
    func downloadPlaceholder(at sourceURL: URL) async throws
}

struct ImportSingleFilePreflightRequest: Equatable {
    var repoPath: String
    var sourceURL: URL
    var category: String
    var targetFilename: String
}

struct ImportSingleFilePreflightResult: Equatable {
    var sourceSizeBytes: Int64?
    var sourceModifiedAt: Int64?
    var hashSha256: String?
    var targetRelativePath: String
    var conflict: ImportSingleFileConflict
    var keepBothTargetRelativePath: String?
    var existingPaths: Set<String> = []
    var existingFile: FileEntrySnapshot?

    var statusMessage: String {
        switch conflict {
        case .none:
            "hash 预检完成；未发现内容重复。"
        case let .invalidFilename(message):
            message
        case let .name(path):
            "目标目录中已经存在同名文件，但内容不同：\(path)"
        case let .duplicate(path):
            "hash 重复：\(path)"
        case .iCloudPlaceholder:
            "文件尚未从 iCloud 下载。需要下载后才能导入或计算 hash。"
        case let .iCloudDownloadFailed(_, reason):
            "iCloud 下载失败：\(reason)"
        case let .corePreviewUnavailable(message):
            message
        case let .sourceUnavailable(message), let .error(message):
            message
        }
    }

    func importBlockingReason() -> String? {
        switch conflict {
        case .none:
            nil
        case let .invalidFilename(message):
            message
        case .name, .duplicate:
            ImportSingleFileConflictPage(conflict: conflict)?.blockingReason ?? "请先完成冲突处理"
        case .iCloudPlaceholder:
            "iCloud placeholder 需要下载后才能导入"
        case .iCloudDownloadFailed:
            "iCloud 下载失败后请重试下载或切换本地资料库"
        case let .corePreviewUnavailable(message):
            message
        case let .sourceUnavailable(message), let .error(message):
            message
        }
    }
}

enum ImportSingleFilePreflightStatus: Equatable {
    case idle
    case checking(String)
    case ready(ImportSingleFilePreflightResult)
    case blocked(ImportSingleFilePreflightResult)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            nil
        case let .checking(message):
            message
        case let .ready(result), let .blocked(result):
            result.statusMessage
        }
    }

    func importBlockingReason() -> String? {
        switch self {
        case .idle:
            "导入预检未开始"
        case .checking:
            "Checking duplicate..."
        case let .ready(result), let .blocked(result):
            result.importBlockingReason()
        }
    }
}

enum ImportSingleFileConflict: Equatable {
    case none
    case invalidFilename(String)
    case name(path: String)
    case duplicate(existingPath: String)
    case iCloudPlaceholder(path: String)
    case iCloudDownloadFailed(path: String, reason: String)
    case corePreviewUnavailable(String)
    case sourceUnavailable(String)
    case error(String)
}

enum ImportSingleFileConflictPage: Equatable {
    case duplicate
    case name

    init?(conflict: ImportSingleFileConflict) {
        switch conflict {
        case .duplicate:
            self = .duplicate
        case .name:
            self = .name
        case .none, .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return nil
        }
    }

    var routeLabel: String {
        switch self {
        case .duplicate:
            "S1-22 conflict-duplicate"
        case .name:
            "S1-23 conflict-name"
        }
    }

    var title: String {
        switch self {
        case .duplicate:
            "冲突：内容重复"
        case .name:
            "冲突：目标位置已有同名文件"
        }
    }

    var summary: String {
        switch self {
        case .duplicate:
            "资料库中已存在相同内容的文件。请先进入冲突处理区域决定后续策略。"
        case .name:
            "目标目录中已经存在同名文件，但内容不同。"
        }
    }

    var blockingReason: String {
        "请先完成 \(routeLabel) 处理"
    }
}

struct SingleFileReplaceConfirmationContext: Equatable, Identifiable {
    var existingPath: String
    var existingSizeBytes: Int64?
    var existingModifiedAt: Int64?
    var incomingPath: String
    var incomingSizeBytes: Int64?
    var incomingModifiedAt: Int64?
    var targetRelativePath: String
    var isTrashAvailable: Bool

    var id: String {
        "\(existingPath)|\(incomingPath)|\(targetRelativePath)"
    }

    func decision(understandsReplace: Bool) -> SingleFileReplaceConfirmationDecision {
        SingleFileReplaceConfirmationDecision(
            context: self,
            understandsReplace: understandsReplace
        )
    }
}

struct SingleFileReplaceConfirmationDecision: Equatable {
    var context: SingleFileReplaceConfirmationContext
    var understandsReplace: Bool
}

enum ImportSingleFileReplaceOptionVisibility: Equatable {
    case hidden
    case enabled
    case disabled

    var label: String {
        switch self {
        case .hidden:
            "Replace hidden"
        case .enabled:
            "Replace available"
        case .disabled:
            "Replace requires system Trash"
        }
    }

    var blockingReason: String {
        switch self {
        case .hidden:
            "Replace disabled by advanced settings"
        case .enabled:
            "Replace 必须先进入二次确认"
        case .disabled:
            "Replace requires system Trash"
        }
    }
}

struct CoreImportSingleFilePreflight: ImportSingleFilePreflighting {
    private let fileLoader: any ImportBatchCoreFileLoading

    init(fileLoader: any ImportBatchCoreFileLoading = CoreBridgeBatchFileLoader()) {
        self.fileLoader = fileLoader
    }

    func preflightSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult {
        do {
            let source = try SourcePreflightSnapshot.inspect(sourceURL: request.sourceURL)
            if let validationMessage = ImportSingleFileFilenameValidator
                .validationMessage(for: request.targetFilename) {
                return blockedResult(
                    request: request,
                    sourceSizeBytes: source.sizeBytes,
                    sourceModifiedAt: source.modifiedAt,
                    hashSha256: nil,
                    conflict: .invalidFilename(validationMessage)
                )
            }
            let sourceHash = try ImportSingleFileHasher.sha256Hex(for: request.sourceURL)
            let files = try await fileLoader.loadImportPreviewFiles(repoPath: request.repoPath, categories: [nil])
            return readyResult(
                request: request,
                sourceSizeBytes: source.sizeBytes,
                sourceModifiedAt: source.modifiedAt,
                hashSha256: sourceHash,
                files: files
            )
        } catch let error as ImportSingleFilePreflightError {
            return blockedResult(
                request: request,
                sourceSizeBytes: error.sourceSizeBytes,
                hashSha256: nil,
                conflict: error.conflict
            )
        } catch {
            return blockedResult(
                request: request,
                sourceSizeBytes: nil,
                hashSha256: nil,
                conflict: .error("导入预检失败：\(Self.readableMessage(for: error))")
            )
        }
    }

    private func blockedResult(
        request: ImportSingleFilePreflightRequest,
        sourceSizeBytes: Int64?,
        sourceModifiedAt: Int64? = nil,
        hashSha256: String?,
        conflict: ImportSingleFileConflict
    ) -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: sourceSizeBytes,
            sourceModifiedAt: sourceModifiedAt,
            hashSha256: hashSha256,
            targetRelativePath: ImportSingleFilePreflightTarget.relativePath(
                category: request.category,
                filename: request.targetFilename
            ),
            conflict: conflict,
            keepBothTargetRelativePath: nil
        )
    }

    private func readyResult(
        request: ImportSingleFilePreflightRequest,
        sourceSizeBytes: Int64,
        sourceModifiedAt: Int64?,
        hashSha256: String,
        files: [FileEntrySnapshot]
    ) -> ImportSingleFilePreflightResult {
        let targetRelativePath = ImportSingleFilePreflightTarget.relativePath(
            category: request.category,
            filename: request.targetFilename
        )
        if let duplicate = files.first(where: { $0.hashSha256 == hashSha256 }) {
            return ImportSingleFilePreflightResult(
                sourceSizeBytes: sourceSizeBytes,
                sourceModifiedAt: sourceModifiedAt,
                hashSha256: hashSha256,
                targetRelativePath: targetRelativePath,
                conflict: .duplicate(existingPath: duplicate.path),
                keepBothTargetRelativePath: keepBothTargetRelativePath(
                    preferredPath: targetRelativePath,
                    files: files
                ),
                existingPaths: Set(files.map(\.path)),
                existingFile: duplicate
            )
        }
        if let sameName = files.first(where: { $0.path == targetRelativePath }) {
            return ImportSingleFilePreflightResult(
                sourceSizeBytes: sourceSizeBytes,
                sourceModifiedAt: sourceModifiedAt,
                hashSha256: hashSha256,
                targetRelativePath: targetRelativePath,
                conflict: .name(path: sameName.path),
                keepBothTargetRelativePath: keepBothTargetRelativePath(
                    preferredPath: targetRelativePath,
                    files: files
                ),
                existingPaths: Set(files.map(\.path)),
                existingFile: sameName
            )
        }

        return ImportSingleFilePreflightResult(
            sourceSizeBytes: sourceSizeBytes,
            sourceModifiedAt: sourceModifiedAt,
            hashSha256: hashSha256,
            targetRelativePath: targetRelativePath,
            conflict: .none,
            keepBothTargetRelativePath: nil,
            existingPaths: Set(files.map(\.path))
        )
    }

    private func keepBothTargetRelativePath(
        preferredPath: String,
        files: [FileEntrySnapshot]
    ) -> String? {
        ImportSingleFileDuplicateKeepBothPreview.nextAvailablePath(
            preferredPath: preferredPath,
            existingPaths: Set(files.map(\.path))
        )
    }

    private static func readableMessage(for error: Error) -> String {
        guard let coreError = error as? CoreError else {
            return error.localizedDescription
        }

        switch coreError {
        case let .Io(message), let .Db(message), let .Internal(message):
            return message
        case let .Config(reason), let .Classify(reason):
            return reason
        case let .Conflict(path), let .DuplicateFile(path), let .FileNotFound(path),
             let .RepoNotInitialized(path), let .InvalidPath(path), let .ICloudPlaceholder(path),
             let .PermissionDenied(path):
            return path
        }
    }
}

enum ImportSingleFileFilenameValidator {
    private static let invalidScalars = CharacterSet(charactersIn: "/\\\\:*?\"<>|")

    static func validationMessage(for filename: String) -> String? {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "文件名不能为空"
        }
        if trimmed == "." || trimmed == ".." {
            return "文件名不能是 . 或 .."
        }
        if trimmed.rangeOfCharacter(from: invalidScalars) != nil {
            return "文件名不能包含 / \\ : * ? \" < > |"
        }
        return nil
    }

    static func validate(_ filename: String) throws {
        if validationMessage(for: filename) != nil {
            throw CoreError.InvalidPath(path: filename)
        }
    }
}

struct LocalICloudPlaceholderDownloader: ICloudPlaceholderDownloading {
    func downloadPlaceholder(at sourceURL: URL) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: sourceURL)
    }
}

private struct SourcePreflightSnapshot {
    var sizeBytes: Int64
    var modifiedAt: Int64?

    static func inspect(sourceURL: URL) throws -> SourcePreflightSnapshot {
        if ImportSingleFilePreflightTarget.isICloudPlaceholder(sourceURL) {
            throw ImportSingleFilePreflightError(
                .iCloudPlaceholder(path: sourceURL.path),
                sourceSizeBytes: nil
            )
        }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable("来源文件已消失，请重试 preview"),
                sourceSizeBytes: nil
            )
        }
        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable("来源文件不可读，请检查权限"),
                sourceSizeBytes: nil
            )
        }
        let values = try sourceURL.resourceValues(forKeys: [
            .fileSizeKey,
            .isRegularFileKey,
            .contentModificationDateKey
        ])
        guard values.isRegularFile == true else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable("只支持单文件导入"),
                sourceSizeBytes: nil
            )
        }
        return SourcePreflightSnapshot(
            sizeBytes: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate.map { Int64($0.timeIntervalSince1970) }
        )
    }
}

private struct ImportSingleFilePreflightError: Error {
    var conflict: ImportSingleFileConflict
    var sourceSizeBytes: Int64?

    init(_ conflict: ImportSingleFileConflict, sourceSizeBytes: Int64?) {
        self.conflict = conflict
        self.sourceSizeBytes = sourceSizeBytes
    }
}

enum ImportSingleFilePreflightTarget {
    static func relativePath(category: String, filename: String) -> String {
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(cleanCategory.isEmpty ? "inbox" : cleanCategory)/\(cleanName.isEmpty ? "untitled" : cleanName)"
    }

    static func isICloudPlaceholder(_ url: URL) -> Bool {
        if url.path.hasSuffix(".icloud") || url.path.contains(".icloud/") {
            return true
        }
        guard let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
        ]) else {
            return false
        }
        return values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded
    }
}
