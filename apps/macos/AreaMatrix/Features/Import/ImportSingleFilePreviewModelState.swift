import Foundation

struct ImportSingleFileSource: Equatable {
    var fileName: String
    var sourcePath: String
    var sizeBytes: Int64?

    init(url: URL) {
        fileName = url.lastPathComponent
        sourcePath = (url.path as NSString).abbreviatingWithTildeInPath
        sizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }
}

enum ImportSingleFilePreviewStatus: Equatable {
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
            nil
        case .loading:
            L10n.string("正在预览分类...")
        case .ready:
            L10n.string("分类预览完成")
        case let .failed(message), let .unsupported(message):
            message
        }
    }
}

enum ImportSingleFileImportStatus: Equatable {
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
            nil
        case let .importing(mode):
            mode.importingMessage
        case let .imported(entry):
            L10n.format("import.single.imported-file", entry.currentName)
        case let .failed(mapping):
            mapping.userMessage
        case let .blocked(message):
            message
        case let .skippedDuplicate(existingPath):
            L10n.format("import.single.duplicate-skipped", existingPath)
        }
    }
}

enum ImportSingleFileStorageMode: String, CaseIterable, Codable, Equatable, Identifiable {
    case copy = "Copy"
    case move = "Move"
    case indexOnly = "Index-only"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .copy: L10n.string("Copy")
        case .move: L10n.string("Move")
        case .indexOnly: L10n.string("Index-only")
        }
    }

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
            L10n.string("保留原文件，复制到 AreaMatrix 资料库。")
        case .move:
            L10n.string("源文件会从原位置移走，并安全写入 AreaMatrix 资料库。")
        case .indexOnly:
            L10n.string("不复制，只记录引用路径；源文件移动后会缺失。")
        }
    }

    var importingMessage: String {
        switch self {
        case .copy:
            L10n.string("正在复制导入...")
        case .move:
            L10n.string("正在移动导入...")
        case .indexOnly:
            L10n.string("正在写入索引...")
        }
    }

    var importingBlockingMessage: String {
        switch self {
        case .copy:
            L10n.string("正在复制导入")
        case .move:
            L10n.string("正在移动导入")
        case .indexOnly:
            L10n.string("正在写入索引")
        }
    }
}
