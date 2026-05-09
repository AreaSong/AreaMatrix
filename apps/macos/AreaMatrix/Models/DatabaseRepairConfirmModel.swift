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

@MainActor
final class DatabaseRepairConfirmModel: ObservableObject {
    let repoPath: String
    let initialMapping: CoreErrorMappingSnapshot?
    let scanSession: ScanSessionSnapshot?
    let lastOpenedAt: Int64?

    @Published var isMetadataSafetyConfirmed = false
    @Published private(set) var repairState: DatabaseRepairState = .idle
    @Published private(set) var diagnosticsState: MainRepoDiagnosticsState = .idle

    private let metadataRepairer: any CoreMetadataRepairing
    private let diagnosticsCollector: any CoreDiagnosticsCollecting
    private let errorMapper: any CoreErrorMapping

    init(
        repoPath: String,
        scanSession: ScanSessionSnapshot?,
        mapping: CoreErrorMappingSnapshot?,
        lastOpenedAt: Int64?,
        metadataRepairer: any CoreMetadataRepairing,
        diagnosticsCollector: any CoreDiagnosticsCollecting,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.scanSession = scanSession
        initialMapping = mapping
        self.lastOpenedAt = lastOpenedAt
        self.metadataRepairer = metadataRepairer
        self.diagnosticsCollector = diagnosticsCollector
        self.errorMapper = errorMapper
    }

    var canRunFullRescan: Bool {
        isMetadataSafetyConfirmed && !repairState.isRunning && !diagnosticsIsBusy && !diagnosticsFailed
    }

    var canExportDiagnostics: Bool {
        !repairState.isRunning && !diagnosticsIsBusy
    }

    var primaryButtonTitle: String {
        repairState.failure == nil ? "Run Full Rescan" : "Retry Full Rescan"
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
