import AreaMatrixCoreBridgeContract
import AreaMatrixFeatureAI
import Combine
import Foundation

struct RepositorySettingsPathActionError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

struct RepositorySettingsDiagnosticsError: Equatable {
    var message: LocalizedMessage
    var recovery: LocalizedMessage
}

enum RepositorySettingsDiagnosticsState: Equatable {
    case idle
    case confirmingPrivacy
    case collecting
    case collected(DiagnosticsSnapshotSnapshot)
    case failed(RepositorySettingsDiagnosticsError)

    var isConfirmingPrivacy: Bool {
        if case .confirmingPrivacy = self {
            return true
        }
        return false
    }

    var isCollecting: Bool {
        if case .collecting = self {
            return true
        }
        return false
    }
}

enum LocalModelStatusPhase: Equatable {
    case idle
    case checking(LocalizedMessage)
    case failed(LocalModelStatusError)
}

enum LocalModelStatusFeedback: Equatable {
    case success(LocalizedMessage)
    case failed(LocalModelStatusError)
}

struct AISettingsFeatureRowSnapshot: Identifiable, Equatable {
    var feature: AISettingsFeatureKind
    var enabled: Bool
    var providerLabel: String
    var remoteScope: String
    var disabledReason: String?

    var id: String {
        feature.rawValue
    }
}

@MainActor
final class LocalModelStatusModel: ObservableObject {
    nonisolated static let defaultModelID = "areamatrix-local-classifier"

    @Published private(set) var snapshot: LocalModelStatusState?
    @Published private(set) var phase: LocalModelStatusPhase = .idle
    @Published private(set) var feedback: LocalModelStatusFeedback?
    @Published private(set) var isDiagnosticsPresented = false

    let repoPath: String
    let modelID: String
    let storageLocation: String
    private let statusReader: any CoreLocalModelStatusReading
    private let installHelpOpener: any LocalModelInstallHelpOpening
    private let folderOpener: any LocalModelFolderOpening
    private let diagnosticsCopier: any LocalModelDiagnosticsCopying
    private let errorMapper: any CoreErrorMapping
    private var cachedStatus: LocalModelCachedStatusState?

    init(
        repoPath: String,
        modelID: String = LocalModelStatusModel.defaultModelID,
        storageLocation: String? = nil,
        storageLocationProvider: any LocalModelStorageLocationProviding,
        statusReader: any CoreLocalModelStatusReading,
        installHelpOpener: any LocalModelInstallHelpOpening,
        folderOpener: any LocalModelFolderOpening,
        diagnosticsCopier: any LocalModelDiagnosticsCopying,
        errorMapper: any CoreErrorMapping
    ) {
        self.repoPath = repoPath
        self.modelID = modelID
        self.storageLocation = storageLocation ?? storageLocationProvider.defaultStorageLocation()
        self.statusReader = statusReader
        self.installHelpOpener = installHelpOpener
        self.folderOpener = folderOpener
        self.diagnosticsCopier = diagnosticsCopier
        self.errorMapper = errorMapper
    }

    var isChecking: Bool {
        if case .checking = phase { return true }
        return false
    }

    var statusText: String {
        L10n.format("settings.repository.actionStatus", availabilityLabel)
    }

    var availabilityLabel: String {
        switch snapshot?.availability ?? .unknown {
        case .unknown: L10n.string("Unknown")
        case .ready: L10n.string("Ready")
        case .notInstalled: L10n.string("Not installed")
        case .pathUnreadable: L10n.string("Path unreadable")
        case .versionIncompatible: L10n.string("Version incompatible")
        case .checking: L10n.string("Checking")
        case .verifying: L10n.string("Verifying")
        case .loading: L10n.string("Loading")
        case .corrupted: L10n.string("Corrupted")
        case .runtimeFailed: L10n.string("Runtime failed")
        case .error: L10n.string("Error")
        }
    }

    var statusDetail: String {
        Self.statusDetail(for: snapshot?.availability ?? .unknown)
    }

    var formattedSize: String {
        guard let sizeBytes = snapshot?.sizeBytes else { return L10n.string("Unknown") }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var lastCheckedLabel: String {
        guard let timestamp = snapshot?.lastCheckedAt else { return L10n.string("Never") }
        return Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(date: .abbreviated, time: .shortened)
    }

    var canOpenModelLocation: Bool {
        !isChecking && snapshot?.recommendedAction == .openModelLocation
    }

    var canRunHealthCheck: Bool {
        guard let availability = snapshot?.availability else { return false }
        return !isChecking && [.versionIncompatible, .runtimeFailed, .error].contains(availability)
    }

    var repairUnavailableReason: String? {
        guard snapshot?.recommendedAction == .repairMetadata || snapshot?.availability == .corrupted else {
            return nil
        }
        return L10n.string("Repair metadata from the diagnostics screen before running another local model check.")
    }

    func checkStatus() async {
        guard !isChecking else { return }
        phase = .checking(cachedStatus == nil
            ? L10n.message("Checking local model status...")
            : L10n.message("Retrying local model status..."))
        feedback = nil
        do {
            let status = try await statusReader.getLocalModelStatus(repoPath: repoPath, request: statusRequest())
            snapshot = status
            cachedStatus = status.cachedStatus
            phase = .idle
        } catch {
            phase = await .failed(localModelError(
                for: error,
                message: L10n.message("Local model status could not be checked."),
                fallbackRecovery: L10n.message("Retry status check")
            ))
        }
    }

    func openInstallHelp() {
        feedback = nil
        do {
            try installHelpOpener.openLocalModelInstallHelp()
            feedback = .success(L10n.message("Install help opened. Return here and run Retry status check."))
        } catch {
            feedback = .failed(LocalModelStatusError(
                message: L10n.message("Install help could not be opened."),
                recovery: L10n.message("Retry or use diagnostics."),
                detail: error.localizedDescription
            ))
        }
    }

    func openModelLocation() async {
        guard !isChecking else { return }
        feedback = nil
        do {
            let location = try await statusReader.locateLocalModelFolder(repoPath: repoPath, request: folderRequest())
            guard location.openable else {
                feedback = .failed(LocalModelStatusError(
                    message: L10n.message("Model location could not be opened."),
                    recovery: L10n.message("Retry status check or open install help."),
                    detail: location.unavailableReason ?? L10n.string("The folder is not available.")
                ))
                return
            }
            try folderOpener.openLocalModelFolder(location)
            feedback = .success(L10n.message("Model location opened."))
        } catch {
            feedback = await .failed(localModelError(
                for: error,
                message: L10n.message("Model location could not be opened."),
                fallbackRecovery: L10n.message("Retry status check")
            ))
        }
    }

    func showDiagnostics() {
        isDiagnosticsPresented = true
    }

    func closeDiagnostics() {
        isDiagnosticsPresented = false
    }

    func copyDiagnosticsSummary() {
        let summary = snapshot?.diagnosticsSummary ?? L10n.string("Local model status has not been checked yet.")
        do {
            try diagnosticsCopier.copyLocalModelDiagnostics(summary)
            feedback = .success(L10n.message("Diagnostics summary copied."))
        } catch {
            feedback = .failed(LocalModelStatusError(
                message: L10n.message("Diagnostics summary could not be copied."),
                recovery: L10n.message("Retry copy."),
                detail: error.localizedDescription
            ))
        }
    }

    private func statusRequest() -> LocalModelStatusRequestState {
        LocalModelStatusRequestState(
            modelID: modelID,
            storageLocation: storageLocation,
            cachedStatus: cachedStatus
        )
    }

    private func folderRequest() -> LocalModelFolderRequestState {
        LocalModelFolderRequestState(modelID: modelID, storageLocation: storageLocation)
    }

    private func localModelError(
        for error: Error,
        message: LocalizedMessage,
        fallbackRecovery: LocalizedMessage
    ) async -> LocalModelStatusError {
        if let mapping = await errorMapper.mapCoreErrorIfPresent(error) {
            return LocalModelStatusError(
                message: message,
                recovery: mapping.recoveryMessage(fallback: fallbackRecovery),
                detail: mapping.userMessage
            )
        }
        return LocalModelStatusError(message: message, recovery: fallbackRecovery, detail: error.localizedDescription)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func statusDetail(for availability: LocalModelAvailabilityState) -> String {
        switch availability {
        case .unknown: L10n.string("Local model status has not been checked yet.")
        case .ready: L10n.string("Local model runtime is available.")
        case .notInstalled: L10n.string("Local model is not installed.")
        case .pathUnreadable: L10n.string("Local model path cannot be read.")
        case .versionIncompatible: L10n.string("Local model version is not compatible.")
        case .checking: L10n.string("Checking local model status...")
        case .verifying: L10n.string("Verifying model manifest...")
        case .loading: L10n.string("Loading model runtime...")
        case .corrupted: L10n.string("Model files are corrupted.")
        case .runtimeFailed: L10n.string("Runtime failed to start.")
        case .error: L10n.string("Local model status is not available yet.")
        }
    }
}
