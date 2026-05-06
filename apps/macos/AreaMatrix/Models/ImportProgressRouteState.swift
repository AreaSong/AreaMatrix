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

    init(sourceOpening: RepositoryOpeningResult, currentPath: String, remaining: Int = 1) {
        self.sourceOpening = sourceOpening
        status = .running
        completed = 0
        failed = 0
        self.remaining = remaining
        self.currentPath = currentPath
    }

    init(
        sourceOpening: RepositoryOpeningResult,
        currentPath: String,
        status: Status,
        completed: Int,
        failed: Int,
        remaining: Int
    ) {
        self.sourceOpening = sourceOpening
        self.status = status
        self.completed = completed
        self.failed = failed
        self.remaining = remaining
        self.currentPath = currentPath
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
        return "已完成 \(completed)，失败 \(failed)，剩余 \(remaining)"
    }

    var titleText: String {
        isFailed ? "导入已暂停" : "正在导入 1 个文件"
    }

    var detailsButtonTitle: String {
        "View details"
    }
}
