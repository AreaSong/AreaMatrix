import Foundation

struct MainLoadingState: Equatable, Sendable {
    var repoPath: String
    var scanSession: ScanSessionSnapshot?
    var scanSessionErrorMapping: CoreErrorMappingSnapshot?

    init(
        repoPath: String,
        scanSession: ScanSessionSnapshot? = nil,
        scanSessionErrorMapping: CoreErrorMappingSnapshot? = nil
    ) {
        self.repoPath = repoPath
        self.scanSession = scanSession
        self.scanSessionErrorMapping = scanSessionErrorMapping
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

    var accessibilityStatusText: String {
        [
            "Opening repository",
            adoptStatusText,
            adoptProgressText,
            adoptCurrentPathText,
        ].compactMap { $0 }.joined(separator: "。")
    }
}

private extension ScanSessionSnapshot {
    var processedCount: Int64 {
        inserted + updated + skipped
    }
}
