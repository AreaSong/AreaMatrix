import Foundation

enum MainLoadingTreeState: Equatable, Sendable {
    case loading
    case loaded(RepositoryTreeNodeSnapshot)
    case failed(CoreErrorMappingSnapshot)

    var loadedTree: RepositoryTreeNodeSnapshot? {
        guard case .loaded(let tree) = self else { return nil }
        return tree
    }
}

enum MainLoadingRecoveryState: Equatable, Sendable {
    case checking
    case completed(RecoveryReportSnapshot?)
    case failed(CoreErrorMappingSnapshot)
}

struct MainLoadingState: Equatable, Sendable {
    var repoPath: String
    var startupRecovery: MainLoadingRecoveryState?
    var scanSession: ScanSessionSnapshot?
    var scanSessionErrorMapping: CoreErrorMappingSnapshot?
    var treeLoading: MainLoadingTreeState?
    var repositoryOpeningErrorMapping: CoreErrorMappingSnapshot?

    init(
        repoPath: String,
        startupRecovery: MainLoadingRecoveryState? = nil,
        scanSession: ScanSessionSnapshot? = nil,
        scanSessionErrorMapping: CoreErrorMappingSnapshot? = nil,
        treeLoading: MainLoadingTreeState? = nil,
        repositoryOpeningErrorMapping: CoreErrorMappingSnapshot? = nil
    ) {
        self.repoPath = repoPath
        self.startupRecovery = startupRecovery
        self.scanSession = scanSession
        self.scanSessionErrorMapping = scanSessionErrorMapping
        self.treeLoading = treeLoading
        self.repositoryOpeningErrorMapping = repositoryOpeningErrorMapping
    }

    var scanStatusText: String? {
        if let scanSessionErrorMapping {
            return "扫描状态不可用：\(scanSessionErrorMapping.userMessage)"
        }

        guard let scanSession else { return nil }

        switch scanSession.status {
        case .running:
            return "正在扫描资料库 \(scanSession.processedCount)"
        case .completed:
            return "\(scanSession.kind.completedStatusPrefix) \(scanSession.processedCount)"
        case .paused:
            return "\(scanSession.kind.pausedStatusPrefix) \(scanSession.processedCount)"
        case .failed:
            return "\(scanSession.kind.failedStatusPrefix) \(scanSession.processedCount)"
        case .interrupted:
            return "\(scanSession.kind.interruptedStatusPrefix) \(scanSession.processedCount)"
        }
    }

    var scanProgressText: String? {
        guard let scanSession else { return nil }
        return """
        新增 \(scanSession.inserted)，更新 \(scanSession.updated)，跳过 \(scanSession.skipped)
        """
    }

    var scanCurrentPathText: String? {
        guard let lastPath = scanSession?.lastPath, !lastPath.isEmpty else { return nil }
        return "当前路径：\(lastPath)"
    }

    var scanWarningText: String? {
        guard let firstError = scanSession?.errors.first else { return nil }
        return firstError
    }

    var recoveryStatusText: String? {
        guard let startupRecovery else { return nil }

        switch startupRecovery {
        case .checking:
            return "正在执行启动恢复检查..."
        case .completed(let report):
            guard let report, report.hasVisibleDetails else {
                return "启动恢复检查完成"
            }

            return """
            启动恢复已完成：清理 \(report.cleanedStagingFiles) 个临时文件，\
            回滚 \(report.revertedStagingDbRows) 条 staging 记录
            """
        case .failed(let mapping):
            return "启动恢复失败：\(mapping.userMessage)"
        }
    }

    var recoveryVisibleReport: RecoveryReportSnapshot? {
        guard case .completed(let report) = startupRecovery else { return nil }
        guard report?.hasVisibleDetails == true else { return nil }
        return report
    }

    var recoveryErrorMapping: CoreErrorMappingSnapshot? {
        guard case .failed(let mapping) = startupRecovery else { return nil }
        return mapping
    }

    var treeStatusText: String? {
        guard let treeLoading else { return nil }

        switch treeLoading {
        case .loading:
            return "正在加载资料库目录..."
        case .loaded(let tree):
            return "目录已加载：\(tree.totalFileCount) 个文件"
        case .failed(let mapping):
            return "目录加载失败：\(mapping.userMessage)"
        }
    }

    var treeRows: [RepositorySidebarRowSnapshot] {
        treeLoading?.loadedTree?.sidebarRows ?? []
    }

    var repositoryOpeningErrorText: String? {
        repositoryOpeningErrorMapping.map { "资料库暂时不可用：\($0.userMessage)" }
    }

    func withRepositoryOpeningError(_ mapping: CoreErrorMappingSnapshot) -> MainLoadingState {
        var state = self
        if state.treeLoading == nil { state.treeLoading = .failed(mapping) }
        state.repositoryOpeningErrorMapping = mapping
        return state
    }

    var accessibilityStatusText: String {
        [
            "Opening repository",
            recoveryStatusText,
            scanAccessibilityStageText,
            scanStatusText,
            scanProgressText,
            scanCurrentPathText,
            treeStatusText,
            repositoryOpeningErrorText,
        ].compactMap { $0 }.joined(separator: "。")
    }

    private var scanAccessibilityStageText: String? {
        guard scanSession != nil || scanSessionErrorMapping != nil else { return nil }
        return "Scanning changes"
    }
}

struct MainLoadingScanRefreshResult: Equatable, Sendable {
    var scanSession: ScanSessionSnapshot?
    var scanSessionErrorMapping: CoreErrorMappingSnapshot?
}

struct MainLoadingTreeRefreshResult: Equatable, Sendable {
    var treeLoading: MainLoadingTreeState
}

struct MainLoadingRefreshUpdate: Equatable, Sendable {
    var scanResult: MainLoadingScanRefreshResult?
    var treeResult: MainLoadingTreeRefreshResult?
}

private extension ScanSessionSnapshot {
    var processedCount: Int64 {
        inserted + updated + skipped
    }
}

private extension ScanSessionKindSnapshot {
    var completedStatusPrefix: String {
        switch self {
        case .adopt:
            return "接管扫描已完成"
        case .reindex:
            return "重新扫描已完成"
        }
    }

    var pausedStatusPrefix: String {
        switch self {
        case .adopt:
            return "接管扫描已暂停"
        case .reindex:
            return "重新扫描已暂停"
        }
    }

    var failedStatusPrefix: String {
        switch self {
        case .adopt:
            return "接管扫描失败"
        case .reindex:
            return "重新扫描失败"
        }
    }

    var interruptedStatusPrefix: String {
        switch self {
        case .adopt:
            return "接管扫描已中断"
        case .reindex:
            return "重新扫描已中断"
        }
    }
}
