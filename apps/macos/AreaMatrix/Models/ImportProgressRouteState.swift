import Foundation

struct ImportProgressRouteState: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case running
        case failed(CoreErrorMappingSnapshot)
    }

    var sourceOpening: RepositoryOpeningResult
    var status: Status
    var completed: Int
    var failed: Int
    var remaining: Int
    var currentPath: String
    var skipped: Int
    var pending: Int

    init(sourceOpening: RepositoryOpeningResult, currentPath: String, remaining: Int = 1) {
        self.sourceOpening = sourceOpening
        status = .running
        completed = 0
        failed = 0
        self.remaining = remaining
        self.currentPath = currentPath
        skipped = 0
        pending = 0
    }

    init(
        sourceOpening: RepositoryOpeningResult,
        currentPath: String,
        status: Status,
        completed: Int,
        failed: Int,
        remaining: Int,
        skipped: Int = 0,
        pending: Int = 0
    ) {
        self.sourceOpening = sourceOpening
        self.status = status
        self.completed = completed
        self.failed = failed
        self.remaining = remaining
        self.currentPath = currentPath
        self.skipped = skipped
        self.pending = pending
    }

    var repoPath: String {
        sourceOpening.config.repoPath
    }

    var errorMapping: CoreErrorMappingSnapshot? {
        guard case .failed(let mapping) = status else { return nil }
        return mapping
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    var toolbarText: String {
        "Importing \(completed) / \(completed + failed + remaining)"
    }

    var bannerText: String {
        if let errorMapping {
            return errorMapping.userMessage
        }
        let extras = resultExtras
        return extras.isEmpty
            ? "已完成 \(completed)，失败 \(failed)，剩余 \(remaining)"
            : "已完成 \(completed)，失败 \(failed)，剩余 \(remaining)，\(extras)"
    }

    var titleText: String {
        if isFailed {
            return "导入已暂停"
        }
        return total <= 1 ? "正在导入 1 个文件" : "正在导入 \(total) 个文件"
    }

    var detailsButtonTitle: String {
        "View details"
    }

    private var total: Int {
        completed + failed + remaining + skipped + pending
    }

    private var resultExtras: String {
        var parts: [String] = []
        if skipped > 0 {
            parts.append("跳过 \(skipped)")
        }
        if pending > 0 {
            parts.append("待下载 \(pending)")
        }
        return parts.joined(separator: "，")
    }
}
