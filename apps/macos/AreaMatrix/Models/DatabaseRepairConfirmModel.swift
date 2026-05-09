import Combine
import Foundation

enum DatabaseRepairProgressStep: String, CaseIterable, Equatable, Sendable {
    case scanningFiles = "Scanning files"
    case rebuildingIndex = "Rebuilding index"
    case reloadingRepository = "Reloading repository"
}

enum DatabaseRepairState: Equatable, Sendable {
    case idle
    case running(DatabaseRepairProgressStep)
    case succeeded(RepairReportSnapshot)
    case failed(CoreErrorMappingSnapshot)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isSucceeded: Bool {
        if case .succeeded = self { return true }
        return false
    }

    var failure: CoreErrorMappingSnapshot? {
        if case .failed(let mapping) = self { return mapping }
        return nil
    }
}

enum DatabaseStartupRecoveryState: Equatable, Sendable {
    case idle
    case checking
    case completed(RecoveryReportSnapshot?)
    case failed(CoreErrorMappingSnapshot)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }
}

@MainActor
final class DatabaseRepairConfirmModel: ObservableObject {
    let repoPath: String
    let initialMapping: CoreErrorMappingSnapshot?
    let scanSession: ScanSessionSnapshot?
    let lastOpenedAt: Int64?

    @Published var isMetadataSafetyConfirmed = false
    @Published private(set) var startupRecoveryState: DatabaseStartupRecoveryState = .idle
    @Published private(set) var repairState: DatabaseRepairState = .idle
    @Published private(set) var diagnosticsState: MainRepoDiagnosticsState = .idle

    private let metadataRepairer: any CoreMetadataRepairing
    private let startupRecoverer: any CoreStartupRecovering
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        scanSession: ScanSessionSnapshot?,
        mapping: CoreErrorMappingSnapshot?,
        lastOpenedAt: Int64?,
        metadataRepairer: any CoreMetadataRepairing,
        startupRecoverer: any CoreStartupRecovering = CoreBridge(),
        diagnosticsCollector: any CoreDiagnosticsCollecting,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.scanSession = scanSession
        initialMapping = mapping
        self.lastOpenedAt = lastOpenedAt
        self.metadataRepairer = metadataRepairer
        self.startupRecoverer = startupRecoverer
        self.diagnosticsCollector = diagnosticsCollector
        self.errorMapper = errorMapper
    }

    var canRunFullRescan: Bool {
        isMetadataSafetyConfirmed &&
            !repairState.isRunning &&
            !startupRecoveryState.isChecking &&
            !diagnosticsIsBusy &&
            !diagnosticsFailed
    }

    var canExportDiagnostics: Bool {
        !repairState.isRunning && !startupRecoveryState.isChecking && !diagnosticsIsBusy
    }

    var primaryButtonTitle: String {
        repairState.failure == nil ? "Run Full Rescan" : "Retry Full Rescan"
    }

    func runStartupRecoveryCheckIfNeeded() async {
        guard case .idle = startupRecoveryState else { return }
        await runStartupRecoveryCheck()
    }

    func retryStartupRecovery() async {
        guard !startupRecoveryState.isChecking else { return }
        await runStartupRecoveryCheck()
    }

    func runFullRescan() async {
        guard canRunFullRescan else { return }

        diagnosticsState = .idle
        repairState = .running(.scanningFiles)

        do {
            let report = try await metadataRepairer.repairMetadata(
                repoPath: repoPath,
                options: RepairOptionsSnapshot(fullRescan: true, preserveDiagnosticsSnapshot: true)
            )
            repairState = .succeeded(report)
        } catch {
            repairState = .failed(await mapError(error))
        }
    }

    func requestDiagnosticsExport() {
        guard canExportDiagnostics else { return }
        diagnosticsState = .confirmingPrivacy
    }

    func cancelDiagnosticsExport() {
        guard case .confirmingPrivacy = diagnosticsState else { return }
        diagnosticsState = .idle
    }

    func collectDiagnostics() async {
        guard case .confirmingPrivacy = diagnosticsState else { return }

        diagnosticsState = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            diagnosticsState = .collected(snapshot)
        } catch {
            diagnosticsState = .failed(await mapError(error))
        }
    }

    private func runStartupRecoveryCheck() async {
        startupRecoveryState = .checking

        do {
            let report = try await startupRecoverer.recoverOnStartup(repoPath: repoPath)
            startupRecoveryState = .completed(report.hasVisibleDetails ? report : nil)
        } catch {
            startupRecoveryState = .failed(await mapError(error))
        }
    }

    private var diagnosticsIsBusy: Bool {
        if case .collecting = diagnosticsState { return true }
        return false
    }

    private var diagnosticsFailed: Bool {
        if case .failed = diagnosticsState { return true }
        return false
    }

    private func mapError(_ error: Error) async -> CoreErrorMappingSnapshot {
        if let coreError = error as? CoreError {
            return await errorMapper.mapCoreError(coreError)
        }

        return await errorMapper.mapCoreError(CoreError.Internal(message: error.localizedDescription))
    }
}
