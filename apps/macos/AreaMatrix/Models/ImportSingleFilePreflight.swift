import Foundation

protocol ImportSingleFilePreflighting: Sendable {
    func preflightSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult
}

protocol ICloudPlaceholderDownloading: Sendable {
    func downloadPlaceholder(at sourceURL: URL) async throws
}

protocol CoreImportPreviewing: Sendable {
    func previewSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async throws -> ImportSingleFilePreflightResult
}

struct ImportSingleFilePreflightRequest: Equatable, Sendable {
    var repoPath: String
    var sourceURL: URL
    var category: String
    var targetFilename: String
    var allowReplaceDuringImport: Bool
    var isTrashAvailable: Bool
}

struct ImportSingleFilePreflightResult: Equatable, Sendable {
    var sourceSizeBytes: Int64?
    var hashSha256: String?
    var targetRelativePath: String
    var conflict: ImportSingleFileConflict
    var replaceOptionVisibility: ImportSingleFileReplaceOptionVisibility

    var statusMessage: String {
        switch conflict {
        case .none:
            return "preview/hash/conflict precheck 完成：冲突：无"
        case .invalidFilename(let message):
            return message
        case .name(let path):
            return "目标同名：\(path)"
        case .duplicate(let path):
            return "hash 重复：\(path)"
        case .iCloudPlaceholder:
            return "文件尚未从 iCloud 下载。需要下载后才能导入或计算 hash。"
        case .iCloudDownloadFailed(_, let reason):
            return "iCloud 下载失败：\(reason)"
        case .corePreviewUnavailable(let message):
            return message
        case .sourceUnavailable(let message), .error(let message):
            return message
        }
    }

    func importBlockingReason(isReplaceConfirmed: Bool) -> String? {
        switch conflict {
        case .none:
            return nil
        case .invalidFilename(let message):
            return message
        case .name, .duplicate:
            if replaceOptionVisibility == .enabled, isReplaceConfirmed {
                return nil
            }
            return ImportSingleFileConflictPage(conflict: conflict)?.blockingReason ?? "请先完成冲突处理"
        case .iCloudPlaceholder:
            return "iCloud placeholder 需要下载后才能导入"
        case .iCloudDownloadFailed:
            return "iCloud 下载失败后请重试下载或切换本地资料库"
        case .corePreviewUnavailable(let message):
            return message
        case .sourceUnavailable(let message), .error(let message):
            return message
        }
    }

    func replaceConfirmationContext(
        incomingPath: String
    ) -> ImportSingleFileReplaceConfirmationContext? {
        guard replaceOptionVisibility == .enabled else { return nil }
        let existingPath: String
        switch conflict {
        case .invalidFilename:
            return nil
        case .name(let path):
            existingPath = path
        case .duplicate(let existing):
            existingPath = existing
        case .none, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable, .sourceUnavailable, .error:
            return nil
        }
        return ImportSingleFileReplaceConfirmationContext(
            existingPath: existingPath,
            incomingPath: incomingPath,
            incomingSizeBytes: sourceSizeBytes,
            targetRelativePath: targetRelativePath,
            isTrashAvailable: replaceOptionVisibility == .enabled
        )
    }
}

enum ImportSingleFilePreflightStatus: Equatable, Sendable {
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
            return nil
        case .checking(let message):
            return message
        case .ready(let result), .blocked(let result):
            return result.statusMessage
        }
    }

    func importBlockingReason(isReplaceConfirmed: Bool) -> String? {
        switch self {
        case .idle:
            return "导入预检未开始"
        case .checking:
            return "正在检查 preview/hash/conflict precheck"
        case .ready(let result), .blocked(let result):
            return result.importBlockingReason(isReplaceConfirmed: isReplaceConfirmed)
        }
    }
}

enum ImportSingleFileConflict: Equatable, Sendable {
    case none
    case invalidFilename(String)
    case name(path: String)
    case duplicate(existingPath: String)
    case iCloudPlaceholder(path: String)
    case iCloudDownloadFailed(path: String, reason: String)
    case corePreviewUnavailable(String)
    case sourceUnavailable(String)
    case error(String)

    var isConflict: Bool {
        switch self {
        case .name, .duplicate:
            return true
        case .none, .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return false
        }
    }
}

enum ImportSingleFileConflictPage: Equatable, Sendable {
    case duplicate
    case nameConflict

    init?(conflict: ImportSingleFileConflict) {
        switch conflict {
        case .duplicate:
            self = .duplicate
        case .name:
            self = .nameConflict
        case .none, .invalidFilename, .iCloudPlaceholder, .iCloudDownloadFailed, .corePreviewUnavailable,
             .sourceUnavailable, .error:
            return nil
        }
    }

    var routeLabel: String {
        switch self {
        case .duplicate:
            return "S1-22 conflict-duplicate"
        case .nameConflict:
            return "S1-23 conflict-name"
        }
    }

    var title: String {
        switch self {
        case .duplicate:
            return "冲突：内容重复"
        case .nameConflict:
            return "冲突：目标位置已有同名文件"
        }
    }

    var summary: String {
        switch self {
        case .duplicate:
            return "资料库中已存在相同内容的文件。请先进入冲突处理区域决定后续策略。"
        case .nameConflict:
            return "目标目录中已经存在同名文件，但内容不同。请先进入冲突处理区域决定后续策略。"
        }
    }

    var blockingReason: String {
        "请先完成 \(routeLabel) 处理"
    }
}

struct ImportSingleFileReplaceConfirmationContext: Equatable, Identifiable, Sendable {
    var existingPath: String
    var incomingPath: String
    var incomingSizeBytes: Int64?
    var targetRelativePath: String
    var isTrashAvailable: Bool

    var id: String {
        "\(existingPath)|\(incomingPath)|\(targetRelativePath)"
    }

    func decision(understandsReplace: Bool) -> ImportSingleFileReplaceConfirmationDecision {
        ImportSingleFileReplaceConfirmationDecision(
            context: self,
            understandsReplace: understandsReplace
        )
    }
}

struct ImportSingleFileReplaceConfirmationDecision: Equatable, Sendable {
    var context: ImportSingleFileReplaceConfirmationContext
    var understandsReplace: Bool
}

enum ImportSingleFileReplaceOptionVisibility: Equatable, Sendable {
    case hidden
    case enabled
    case disabled

    var label: String {
        switch self {
        case .hidden:
            return "Replace hidden"
        case .enabled:
            return "Replace available"
        case .disabled:
            return "Replace requires system Trash"
        }
    }

    var blockingReason: String {
        switch self {
        case .hidden:
            return "Replace disabled by advanced settings"
        case .enabled:
            return "Replace 必须先进入二次确认"
        case .disabled:
            return "Replace requires system Trash"
        }
    }
}

struct CoreImportSingleFilePreflight: ImportSingleFilePreflighting {
    private let previewer: any CoreImportPreviewing

    init(previewer: any CoreImportPreviewing = CoreBridge()) {
        self.previewer = previewer
    }

    func preflightSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult {
        do {
            let source = try SourcePreflightSnapshot.inspect(sourceURL: request.sourceURL)
            if let validationMessage = ImportSingleFileFilenameValidator.validationMessage(for: request.targetFilename) {
                return blockedResult(
                    request: request,
                    sourceSizeBytes: source.sizeBytes,
                    conflict: .invalidFilename(validationMessage)
                )
            }
            do {
                return try await previewer.previewSingleFileImport(request: request)
            } catch {
                return blockedResult(
                    request: request,
                    sourceSizeBytes: source.sizeBytes,
                    conflict: previewConflict(for: error)
                )
            }
        } catch let error as ImportSingleFilePreflightError {
            return blockedResult(request: request, sourceSizeBytes: error.sourceSizeBytes, conflict: error.conflict)
        } catch {
            return blockedResult(
                request: request,
                sourceSizeBytes: nil,
                conflict: .error("导入预检失败：\(error.localizedDescription)")
            )
        }
    }

    private func blockedResult(
        request: ImportSingleFilePreflightRequest,
        sourceSizeBytes: Int64?,
        conflict: ImportSingleFileConflict
    ) -> ImportSingleFilePreflightResult {
        ImportSingleFilePreflightResult(
            sourceSizeBytes: sourceSizeBytes,
            hashSha256: nil,
            targetRelativePath: ImportSingleFilePreflightTarget.relativePath(
                category: request.category,
                filename: request.targetFilename
            ),
            conflict: conflict,
            replaceOptionVisibility: replaceVisibility(for: conflict, request: request)
        )
    }

    private func replaceVisibility(
        for conflict: ImportSingleFileConflict,
        request: ImportSingleFilePreflightRequest
    ) -> ImportSingleFileReplaceOptionVisibility {
        guard conflict.isConflict else { return .hidden }
        if !request.allowReplaceDuringImport { return .hidden }
        return request.isTrashAvailable ? .enabled : .disabled
    }

    private func previewConflict(for error: Error) -> ImportSingleFileConflict {
        if let bridgeError = error as? CoreBridgeError {
            return .corePreviewUnavailable(Self.previewUnavailableMessage(bridgeError.localizedDescription))
        }
        if error is CoreError {
            return .error("Core preview_import 预检失败：\(error.localizedDescription)")
        }
        return .error("Core preview_import 预检失败：\(error.localizedDescription)")
    }

    private static func previewUnavailableMessage(_ detail: String) -> String {
        "Core preview_import 尚未在 UDL / generated bindings 中接入，无法完成 preview/hash/conflict precheck。\(detail)"
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
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw ImportSingleFilePreflightError(
                .sourceUnavailable("只支持单文件导入"),
                sourceSizeBytes: nil
            )
        }
        return SourcePreflightSnapshot(sizeBytes: Int64(values.fileSize ?? 0))
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
            .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]) else {
            return false
        }
        return values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus == .notDownloaded
    }
}
