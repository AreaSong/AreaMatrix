import Foundation

struct ImportSingleFileSource: Equatable, Sendable {
    var fileName: String
    var sourcePath: String
    var sizeBytes: Int64?

    init(url: URL) {
        fileName = url.lastPathComponent
        sourcePath = (url.path as NSString).abbreviatingWithTildeInPath
        sizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }
}

enum ImportSingleFilePreviewStatus: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed(String)
    case unsupported(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .loading:
            return "正在预览分类..."
        case .ready:
            return "分类预览完成"
        case .failed(let message), .unsupported(let message):
            return message
        }
    }
}

enum ImportSingleFileImportStatus: Equatable, Sendable {
    case idle
    case importing(ImportSingleFileStorageMode)
    case imported(FileEntrySnapshot)
    case failed(CoreErrorMappingSnapshot)
    case blocked(String)
    case skippedDuplicate(String)

    var isImporting: Bool {
        if case .importing = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .importing(let mode):
            return mode.importingMessage
        case .imported(let entry):
            return "已导入：\(entry.currentName)"
        case .failed(let mapping):
            return mapping.userMessage
        case .blocked(let message):
            return message
        case .skippedDuplicate(let existingPath):
            return "已跳过重复文件：\(existingPath)"
        }
    }
}

enum ImportSingleFileStorageMode: String, CaseIterable, Equatable, Identifiable, Sendable {
    case copy = "Copy"
    case move = "Move"
    case indexOnly = "Index-only"

    var id: String { rawValue }

    init(coreSnapshotValue: String) {
        switch coreSnapshotValue {
        case "Moved":
            self = .move
        case "Indexed":
            self = .indexOnly
        default:
            self = .copy
        }
    }

    var explanation: String {
        switch self {
        case .copy:
            return "保留原文件，复制到 AreaMatrix 资料库。"
        case .move:
            return "源文件会从原位置移走，并安全写入 AreaMatrix 资料库。"
        case .indexOnly:
            return "不复制，只记录引用路径；源文件移动后会缺失。"
        }
    }

    var importingMessage: String {
        switch self {
        case .copy:
            return "正在复制导入..."
        case .move:
            return "正在移动导入..."
        case .indexOnly:
            return "正在写入索引..."
        }
    }

    var importingBlockingMessage: String {
        switch self {
        case .copy:
            return "正在复制导入"
        case .move:
            return "正在移动导入"
        case .indexOnly:
            return "正在写入索引"
        }
    }

}
