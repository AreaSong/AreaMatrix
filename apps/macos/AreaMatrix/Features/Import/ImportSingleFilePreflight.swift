import Foundation

protocol ImportSingleFilePreflighting: Sendable {
    func preflightSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult
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
        L10n.resolve(statusDisplayText)
    }

    var statusDisplayText: AppDisplayText {
        switch conflict {
        case .none:
            L10n.display("hash 预检完成；未发现内容重复。")
        case let .invalidFilename(message):
            message
        case let .name(path):
            L10n.display("import.preflight.name-conflict", arguments: [.string(path)])
        case let .duplicate(path):
            L10n.display("import.preflight.hash-duplicate", arguments: [.string(path)])
        case .iCloudPlaceholder:
            L10n.display("文件尚未从 iCloud 下载。需要下载后才能导入或计算 hash。")
        case let .iCloudDownloadFailed(_, reason):
            L10n.display(
                "import.preflight.icloud-download-failed",
                arguments: [.string(reason)],
                technicalDetail: reason
            )
        case let .corePreviewUnavailable(message):
            message
        case let .sourceUnavailable(message), let .error(message):
            message
        }
    }

    func importBlockingReason() -> String? {
        importBlockingDisplayText().map(L10n.resolve)
    }

    func importBlockingDisplayText() -> AppDisplayText? {
        switch conflict {
        case .none:
            nil
        case let .invalidFilename(message):
            message
        case .name, .duplicate:
            ImportSingleFileConflictPage(conflict: conflict)?.blockingDisplayText ??
                L10n.display("import.conflict.resolveFirst")
        case .iCloudPlaceholder:
            L10n.display("iCloud placeholder 需要下载后才能导入")
        case .iCloudDownloadFailed:
            L10n.display("iCloud 下载失败后请重试下载或切换本地资料库")
        case let .corePreviewUnavailable(message):
            message
        case let .sourceUnavailable(message), let .error(message):
            message
        }
    }
}

enum ImportSingleFilePreflightStatus: Equatable {
    case idle
    case checking(LocalizedMessage)
    case ready(ImportSingleFilePreflightResult)
    case blocked(ImportSingleFilePreflightResult)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var message: String? {
        displayText.map(L10n.resolve)
    }

    var displayText: AppDisplayText? {
        switch self {
        case .idle:
            nil
        case let .checking(message):
            .localized(message)
        case let .ready(result), let .blocked(result):
            result.statusDisplayText
        }
    }

    func importBlockingReason() -> String? {
        importBlockingDisplayText().map(L10n.resolve)
    }

    func importBlockingDisplayText() -> AppDisplayText? {
        switch self {
        case .idle:
            L10n.display("导入预检未开始")
        case .checking:
            L10n.display("Checking duplicate...")
        case let .ready(result), let .blocked(result):
            result.importBlockingDisplayText()
        }
    }
}

enum ImportSingleFileConflict: Equatable {
    case none
    case invalidFilename(AppDisplayText)
    case name(path: String)
    case duplicate(existingPath: String)
    case iCloudPlaceholder(path: String)
    case iCloudDownloadFailed(path: String, reason: String)
    case corePreviewUnavailable(AppDisplayText)
    case sourceUnavailable(AppDisplayText)
    case error(AppDisplayText)
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
            "duplicate-conflict conflict-duplicate"
        case .name:
            "name-conflict conflict-name"
        }
    }

    var title: String {
        switch self {
        case .duplicate:
            L10n.string("冲突：内容重复")
        case .name:
            L10n.string("冲突：目标位置已有同名文件")
        }
    }

    var summary: String {
        switch self {
        case .duplicate:
            L10n.string("import.conflict.duplicateRequiresResolution")
        case .name:
            L10n.string("目标目录中已经存在同名文件，但内容不同。")
        }
    }

    var blockingReason: String {
        L10n.resolve(blockingDisplayText)
    }

    var blockingDisplayText: AppDisplayText {
        L10n.display("import.preflight.complete-route-first", arguments: [.string(routeLabel)])
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
            L10n.string("Replace hidden")
        case .enabled:
            L10n.string("Replace available")
        case .disabled:
            L10n.string("Replace requires system Trash")
        }
    }

    var blockingReason: String {
        L10n.resolve(blockingDisplayText)
    }

    var blockingDisplayText: AppDisplayText {
        switch self {
        case .hidden:
            L10n.display("Replace disabled by advanced settings")
        case .enabled:
            L10n.display("Replace 必须先进入二次确认")
        case .disabled:
            L10n.display("Replace requires system Trash")
        }
    }
}

struct CoreImportSingleFilePreflight: ImportSingleFilePreflighting {
    private let fileLoader: any ImportBatchCoreFileLoading
    private let sourceInspector: any SourcePreflightInspecting

    init(
        fileLoader: any ImportBatchCoreFileLoading = CoreBridgeBatchFileLoader(),
        sourceInspector: any SourcePreflightInspecting = ImportPlatformServices.sourcePreflightInspector
    ) {
        self.fileLoader = fileLoader
        self.sourceInspector = sourceInspector
    }

    func preflightSingleFileImport(
        request: ImportSingleFilePreflightRequest
    ) async -> ImportSingleFilePreflightResult {
        do {
            let source = try sourceInspector.inspect(sourceURL: request.sourceURL)
            if let validationMessage = ImportSingleFileFilenameValidator
                .validationDisplayText(for: request.targetFilename) {
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
                conflict: .error(
                    L10n.display(
                        "import.preflight.failed",
                        arguments: [.string(Self.readableMessage(for: error))],
                        technicalDetail: Self.readableMessage(for: error)
                    )
                )
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
        guard let context = CoreErrorRawContextSnapshot(error) else {
            return error.localizedDescription
        }

        return context.rawContext
    }
}
