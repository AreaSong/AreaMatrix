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

    init(
        repoPath: String,
        startupRecovery: MainLoadingRecoveryState? = nil,
        scanSession: ScanSessionSnapshot? = nil,
        scanSessionErrorMapping: CoreErrorMappingSnapshot? = nil,
        treeLoading: MainLoadingTreeState? = nil
    ) {
        self.repoPath = repoPath
        self.startupRecovery = startupRecovery
        self.scanSession = scanSession
        self.scanSessionErrorMapping = scanSessionErrorMapping
        self.treeLoading = treeLoading
    }

    var adoptScanSession: ScanSessionSnapshot? {
        guard scanSession?.kind == .adopt else { return nil }
        return scanSession
    }

    var adoptStatusText: String? {
        if let scanSessionErrorMapping {
            return "接管扫描状态不可用：\(scanSessionErrorMapping.userMessage)"
        }

        guard let adoptScanSession else { return nil }

        switch adoptScanSession.status {
        case .running:
            return "正在扫描资料库 \(adoptScanSession.processedCount)"
        case .completed:
            return "接管扫描已完成 \(adoptScanSession.processedCount)"
        case .paused:
            return "接管扫描已暂停 \(adoptScanSession.processedCount)"
        case .failed:
            return "接管扫描失败 \(adoptScanSession.processedCount)"
        case .interrupted:
            return "接管扫描已中断 \(adoptScanSession.processedCount)"
        }
    }

    var adoptProgressText: String? {
        guard let adoptScanSession else { return nil }
        return """
        新增 \(adoptScanSession.inserted)，更新 \(adoptScanSession.updated)，\
        跳过 \(adoptScanSession.skipped)
        """
    }

    var adoptCurrentPathText: String? {
        guard let lastPath = adoptScanSession?.lastPath, !lastPath.isEmpty else { return nil }
        return "当前路径：\(lastPath)"
    }

    var adoptWarningText: String? {
        guard let firstError = adoptScanSession?.errors.first else { return nil }
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

    var accessibilityStatusText: String {
        [
            "Opening repository",
            recoveryStatusText,
            adoptStatusText,
            adoptProgressText,
            adoptCurrentPathText,
            treeStatusText,
        ].compactMap { $0 }.joined(separator: "。")
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
