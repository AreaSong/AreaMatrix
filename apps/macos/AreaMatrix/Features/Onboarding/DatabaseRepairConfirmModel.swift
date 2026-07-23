import Combine
import Foundation

enum DatabaseRepairProgressStep: String, CaseIterable, Equatable {
    case initializingMetadata = "Initializing metadata database"
    case scanningFiles = "Scanning files"
    case rebuildingIndex = "Rebuilding index"
    case reloadingRepository = "Reloading repository"

    var displayName: String {
        switch self {
        case .initializingMetadata: L10n.string("Initializing metadata database")
        case .scanningFiles: L10n.string("Scanning files")
        case .rebuildingIndex: L10n.string("Rebuilding index")
        case .reloadingRepository: L10n.string("Reloading repository")
        }
    }
}

enum DatabaseRepairState: Equatable {
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
        if case let .failed(mapping) = self { return mapping }
        return nil
    }
}

enum DatabaseStartupRecoveryState: Equatable {
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
    private let repositoryWriteCoordinator: RepositoryWriteCoordinator
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private let errorMapper: any CoreErrorMapping
    private var diagnosticsGeneration = 0

    init(
        repoPath: String,
        scanSession: ScanSessionSnapshot?,
        mapping: CoreErrorMappingSnapshot?,
        lastOpenedAt: Int64?,
        metadataRepairer: any CoreMetadataRepairing,
        startupRecoverer: any CoreStartupRecovering,
        repositoryWriteCoordinator: RepositoryWriteCoordinator = AppCoreServices.repositoryWriteCoordinator,
        diagnosticsCollector: any CoreDiagnosticsCollecting,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.scanSession = scanSession
        initialMapping = mapping
        self.lastOpenedAt = lastOpenedAt
        self.metadataRepairer = metadataRepairer
        self.startupRecoverer = startupRecoverer
        self.repositoryWriteCoordinator = repositoryWriteCoordinator
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
        if initialMapping?.kind == .repoNotInitialized {
            return repairState.failure == nil
                ? L10n.string("Initialize & Full Rescan")
                : L10n.string("Retry Initialization & Full Rescan")
        }
        return repairState.failure == nil ? L10n.string("Run Full Rescan") : L10n.string("Retry Full Rescan")
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
        repairState = .running(
            initialMapping?.kind == .repoNotInitialized ? .initializingMetadata : .scanningFiles
        )

        do {
            let report = try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                try await self.metadataRepairer.repairMetadata(
                    repoPath: self.repoPath,
                    options: RepairOptionsSnapshot(fullRescan: true, preserveDiagnosticsSnapshot: true)
                )
            }
            repairState = .succeeded(report)
        } catch {
            repairState = await .failed(errorMapper.mapError(error))
        }
    }

    func requestDiagnosticsExport() {
        guard canExportDiagnostics else { return }
        diagnosticsState = .confirmingPrivacy
    }

    func cancelDiagnosticsExport() {
        guard case .confirmingPrivacy = diagnosticsState else {
            guard case .collecting = diagnosticsState else { return }
            diagnosticsGeneration += 1
            diagnosticsState = .idle
            return
        }
        diagnosticsGeneration += 1
        diagnosticsState = .idle
    }

    func collectDiagnostics() async {
        guard case .confirmingPrivacy = diagnosticsState else { return }

        diagnosticsGeneration += 1
        let generation = diagnosticsGeneration
        diagnosticsState = .collecting
        do {
            let snapshot = try await diagnosticsCollector.createDiagnosticsSnapshot(repoPath: repoPath)
            guard diagnosticsGeneration == generation else { return }
            diagnosticsState = .collected(snapshot)
        } catch {
            guard diagnosticsGeneration == generation else { return }
            diagnosticsState = await .failed(errorMapper.mapError(error))
        }
    }

    private func runStartupRecoveryCheck() async {
        startupRecoveryState = .checking

        do {
            let report = try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                try await self.startupRecoverer.recoverOnStartup(repoPath: self.repoPath)
            }
            startupRecoveryState = .completed(report.hasVisibleDetails ? report : nil)
        } catch {
            startupRecoveryState = await .failed(errorMapper.mapError(error))
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
}
