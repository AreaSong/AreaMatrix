import Foundation

enum MainLoadingTreeState: Equatable {
    case loading
    case loaded(RepositoryTreeNodeSnapshot)
    case failed(CoreErrorMappingSnapshot)

    var loadedTree: RepositoryTreeNodeSnapshot? {
        guard case let .loaded(tree) = self else { return nil }
        return tree
    }
}

enum MainLoadingRecoveryState: Equatable {
    case checking
    case completed(RecoveryReportSnapshot?)
    case failed(CoreErrorMappingSnapshot)
}

struct MainLoadingState: Equatable {
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
            return L10n.format("onboarding.loading.scanUnavailable", scanSessionErrorMapping.userMessage)
        }

        guard let scanSession else { return nil }

        switch scanSession.status {
        case .running:
            return L10n.format("onboarding.loading.scanRunning", scanSession.processedCount)
        case .completed:
            return scanSession.kind.statusText(for: .completed, count: scanSession.processedCount)
        case .paused:
            return scanSession.kind.statusText(for: .paused, count: scanSession.processedCount)
        case .failed:
            return scanSession.kind.statusText(for: .failed, count: scanSession.processedCount)
        case .interrupted:
            return scanSession.kind.statusText(for: .interrupted, count: scanSession.processedCount)
        }
    }

    var scanProgressText: String? {
        guard let scanSession else { return nil }
        return L10n.format(
            "onboarding.loading.scanProgress",
            scanSession.inserted,
            scanSession.updated,
            scanSession.skipped
        )
    }

    var scanCurrentPathText: String? {
        guard let lastPath = scanSession?.lastPath, !lastPath.isEmpty else { return nil }
        return L10n.format("onboarding.loading.currentPath", lastPath)
    }

    var scanWarningText: String? {
        guard let firstError = scanSession?.errors.first else { return nil }
        return firstError
    }

    var recoveryStatusText: String? {
        guard let startupRecovery else { return nil }

        switch startupRecovery {
        case .checking:
            return L10n.string("Checking startup recovery state...")
        case let .completed(report):
            guard let report, report.hasVisibleDetails else {
                return L10n.string("Startup recovery check completed.")
            }
            return L10n.format("onboarding.recovery.completedSummary", report.startupRecoverySummaryText)
        case let .failed(mapping):
            return L10n.format("onboarding.loading.recoveryFailed", mapping.userMessage)
        }
    }

    var recoveryVisibleReport: RecoveryReportSnapshot? {
        guard case let .completed(report) = startupRecovery else { return nil }
        guard report?.hasVisibleDetails == true else { return nil }
        return report
    }

    var recoveryErrorMapping: CoreErrorMappingSnapshot? {
        guard case let .failed(mapping) = startupRecovery else { return nil }
        return mapping
    }

    var treeStatusText: String? {
        guard let treeLoading else { return nil }

        switch treeLoading {
        case .loading:
            return L10n.string("onboarding.loading.loadingTree")
        case let .loaded(tree):
            return L10n.plural("onboarding.loading.treeFileCount", count: tree.totalFileCount)
        case let .failed(mapping):
            return L10n.format("onboarding.loading.treeFailed", mapping.userMessage)
        }
    }

    var treeRows: [RepositorySidebarRowSnapshot] {
        treeLoading?.loadedTree?.sidebarRows ?? []
    }

    var repositoryOpeningErrorText: String? {
        repositoryOpeningErrorMapping.map {
            L10n.format("onboarding.loading.repositoryUnavailable", $0.userMessage)
        }
    }

    func withRepositoryOpeningError(_ mapping: CoreErrorMappingSnapshot) -> MainLoadingState {
        var state = self
        if state.treeLoading == nil { state.treeLoading = .failed(mapping) }
        state.repositoryOpeningErrorMapping = mapping
        return state
    }

    var accessibilityStatusText: String {
        [
            L10n.string("onboarding.loading.opening"),
            recoveryStatusText,
            scanAccessibilityStatusText,
            scanStatusText,
            scanProgressText,
            scanCurrentPathText,
            treeStatusText,
            repositoryOpeningErrorText
        ].compactMap { $0 }.joined(separator: "。")
    }

    private var scanAccessibilityStatusText: String? {
        guard scanSession != nil || scanSessionErrorMapping != nil else { return nil }
        return L10n.string("onboarding.loading.scanning")
    }
}

struct MainLoadingScanRefreshResult: Equatable {
    var scanSession: ScanSessionSnapshot?
    var scanSessionErrorMapping: CoreErrorMappingSnapshot?
}

struct MainLoadingTreeRefreshResult: Equatable {
    var treeLoading: MainLoadingTreeState
}

struct MainLoadingRefreshUpdate: Equatable {
    var scanResult: MainLoadingScanRefreshResult?
    var treeResult: MainLoadingTreeRefreshResult?
}

private extension ScanSessionSnapshot {
    var processedCount: Int64 {
        inserted + updated + skipped
    }
}

private extension ScanSessionKindSnapshot {
    func statusText(for status: ScanSessionStatusSnapshot, count: Int64) -> String {
        L10n.format("onboarding.loading.scanStatus", statusPrefix(for: status), count)
    }

    private func statusPrefix(for status: ScanSessionStatusSnapshot) -> String {
        switch (status, self) {
        case (.running, _):
            L10n.string("正在扫描资料库")
        case (.completed, .adopt):
            L10n.string("onboarding.initializing.scanCompleted")
        case (.completed, .reindex):
            L10n.string("onboarding.loading.reindexCompleted")
        case (.paused, .adopt):
            L10n.string("onboarding.initializing.scanPaused")
        case (.paused, .reindex):
            L10n.string("onboarding.loading.reindexPaused")
        case (.failed, .adopt):
            L10n.string("onboarding.initializing.scanFailed")
        case (.failed, .reindex):
            L10n.string("onboarding.loading.reindexFailed")
        case (.interrupted, .adopt):
            L10n.string("onboarding.initializing.scanInterrupted")
        case (.interrupted, .reindex):
            L10n.string("onboarding.loading.reindexInterrupted")
        }
    }
}
