import Combine
import Foundation

enum DatabaseRepairProgressStep: String, CaseIterable, Equatable {
    case inspectingMetadata = "Inspecting metadata"
    case initializingMetadata = "Initializing metadata database"
    case repairingMetadata = "Repairing metadata"
    case scanningFiles = "Scanning files"

    var displayName: String {
        switch self {
        case .inspectingMetadata: L10n.string("Inspecting metadata")
        case .initializingMetadata: L10n.string("Initializing metadata database")
        case .repairingMetadata: L10n.string("Repairing metadata")
        case .scanningFiles: L10n.string("Scanning files")
        }
    }
}

enum DatabaseRepairPreflightState: Equatable {
    case idle
    case loading
    case ready(RepairMetadataPreflightSnapshot)
    case failed(CoreErrorMappingSnapshot)

    var snapshot: RepairMetadataPreflightSnapshot? {
        if case let .ready(snapshot) = self { return snapshot }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
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

enum DatabaseRescanState: Equatable {
    case idle
    case running
    case succeeded(ReindexReportSnapshot)
    case failed(CoreErrorMappingSnapshot)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isSucceeded: Bool {
        if case .succeeded = self { return true }
        return false
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
    @Published var isRescanConfirmed = false
    @Published var selectedRecoveryLanguage: RepositoryContentLanguage?
    @Published private(set) var preflightState: DatabaseRepairPreflightState = .idle
    @Published private(set) var startupRecoveryState: DatabaseStartupRecoveryState = .idle
    @Published private(set) var repairState: DatabaseRepairState = .idle
    @Published private(set) var rescanState: DatabaseRescanState = .idle
    @Published private(set) var diagnosticsState: MainRepoDiagnosticsState = .idle

    private let metadataRepairer: any CoreMetadataRepairing
    private let repositoryReindexer: any CoreRepositoryReindexing
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
        repositoryReindexer: any CoreRepositoryReindexing = CoreBridge(),
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
        self.repositoryReindexer = repositoryReindexer
        self.startupRecoverer = startupRecoverer
        self.repositoryWriteCoordinator = repositoryWriteCoordinator
        self.diagnosticsCollector = diagnosticsCollector
        self.errorMapper = errorMapper
    }

    var canRunMetadataRepair: Bool {
        isMetadataSafetyConfirmed &&
            selectedRepairPolicy != nil &&
            !preflightState.isLoading &&
            !repairState.isRunning &&
            !rescanState.isRunning &&
            !startupRecoveryState.isChecking &&
            !diagnosticsIsBusy &&
            !diagnosticsFailed
    }

    var canRunRescan: Bool {
        repairState.isSucceeded &&
            isRescanConfirmed &&
            !rescanState.isRunning &&
            !diagnosticsIsBusy
    }

    var canExportDiagnostics: Bool {
        !preflightState.isLoading &&
            !repairState.isRunning &&
            !rescanState.isRunning &&
            !startupRecoveryState.isChecking &&
            !diagnosticsIsBusy
    }

    var primaryButtonTitle: String {
        repairState.failure == nil ? L10n.string("Repair Metadata") : L10n.string("Retry Metadata Repair")
    }

    var rescanButtonTitle: String {
        if case .failed = rescanState { return L10n.string("Retry Rescan") }
        return L10n.string("Run Rescan")
    }

    func loadRepairPreflightIfNeeded() async {
        guard case .idle = preflightState else { return }
        await loadRepairPreflight()
    }

    func retryRepairPreflight() async {
        guard !preflightState.isLoading, !repairState.isRunning else { return }
        await loadRepairPreflight()
    }

    func runStartupRecoveryCheckIfNeeded() async {
        guard case .idle = startupRecoveryState else { return }
        await runStartupRecoveryCheck()
    }

    func retryStartupRecovery() async {
        guard !startupRecoveryState.isChecking else { return }
        await runStartupRecoveryCheck()
    }

    func runMetadataRepair() async {
        guard canRunMetadataRepair,
              let preflight = preflightState.snapshot,
              let repositoryLocalePolicy = selectedRepairPolicy
        else { return }

        diagnosticsState = .idle
        let step: DatabaseRepairProgressStep = preflight.localeState == .metadataAbsent
            ? .initializingMetadata
            : .repairingMetadata
        repairState = .running(step)
        do {
            let report = try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                try await self.metadataRepairer.repairMetadata(
                    repoPath: self.repoPath,
                    options: RepairOptionsSnapshot(
                        preserveDiagnosticsSnapshot: true,
                        preflightToken: preflight.preflightToken,
                        repositoryLocalePolicy: repositoryLocalePolicy
                    )
                )
            }
            repairState = .succeeded(report)
            rescanState = .idle
        } catch {
            repairState = await .failed(errorMapper.mapError(error))
            preflightState = .idle
            await loadRepairPreflight()
        }
    }

    func runRescan() async {
        guard canRunRescan else { return }
        rescanState = .running
        do {
            let report = try await repositoryWriteCoordinator.withWriteAccess(repoPath: repoPath) {
                try await self.repositoryReindexer.reindexRepository(repoPath: self.repoPath)
            }
            rescanState = .succeeded(report)
        } catch {
            rescanState = await .failed(errorMapper.mapError(error))
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

    private var selectedRepairPolicy: String? {
        guard let preflight = preflightState.snapshot else { return nil }
        if !preflight.requiresExplicitLocaleSelection {
            return preflight.repositoryLocalePolicy
        }
        guard let selectedRecoveryLanguage,
              selectedRecoveryLanguage.unsupportedIdentifier == nil
        else { return nil }
        return selectedRecoveryLanguage.snapshotValue
    }

    private func loadRepairPreflight() async {
        preflightState = .loading
        selectedRecoveryLanguage = nil
        do {
            let preflight = try await metadataRepairer.preflightRepairMetadata(repoPath: repoPath)
            preflightState = .ready(preflight)
        } catch {
            preflightState = await .failed(errorMapper.mapError(error))
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
