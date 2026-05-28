import Combine
import Foundation

struct RepositorySettingsPathActionError: Equatable {
    var message: String
    var recovery: String
}

struct RepositorySettingsDiagnosticsError: Equatable {
    var message: String
    var recovery: String
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
    case checking(String)
    case failed(LocalModelStatusError)
}

enum LocalModelStatusFeedback: Equatable {
    case success(String)
    case failed(LocalModelStatusError)
}

struct AISettingsFeatureRowSnapshot: Identifiable, Equatable {
    var feature: AISettingsFeatureKind
    var enabled: Bool
    var providerLabel: String
    var remoteScope: String
    var disabledReason: String?

    var id: String { feature.rawValue }
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
        storageLocation: String = LocalModelStatusModel.defaultStorageLocation(),
        statusReader: any CoreLocalModelStatusReading = CoreBridge(),
        installHelpOpener: any LocalModelInstallHelpOpening = NSWorkspaceLocalModelInstallHelpOpener(),
        folderOpener: any LocalModelFolderOpening = NSWorkspaceLocalModelFolderOpener(),
        diagnosticsCopier: any LocalModelDiagnosticsCopying = NSPasteboardLocalModelDiagnosticsCopier(),
        errorMapper: any CoreErrorMapping = CoreBridge()
    ) {
        self.repoPath = repoPath
        self.modelID = modelID
        self.storageLocation = storageLocation
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
        "Status: \(availabilityLabel)"
    }

    var availabilityLabel: String {
        switch snapshot?.availability ?? .unknown {
        case .unknown: "Unknown"
        case .ready: "Ready"
        case .notInstalled: "Not installed"
        case .pathUnreadable: "Path unreadable"
        case .versionIncompatible: "Version incompatible"
        case .checking: "Checking"
        case .verifying: "Verifying"
        case .loading: "Loading"
        case .corrupted: "Corrupted"
        case .runtimeFailed: "Runtime failed"
        case .error: "Error"
        }
    }

    var statusDetail: String {
        Self.statusDetail(for: snapshot?.availability ?? .unknown)
    }

    var formattedSize: String {
        guard let sizeBytes = snapshot?.sizeBytes else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var lastCheckedLabel: String {
        guard let timestamp = snapshot?.lastCheckedAt else { return "Never" }
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
        return "Repair metadata requires a separate repair capability; this page only reads C3-02 status."
    }

    nonisolated static func defaultStorageLocation() -> String {
        if let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return supportURL
                .appendingPathComponent("AreaMatrix", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
                .path
        }
        return NSHomeDirectory() + "/Library/Application Support/AreaMatrix/Models"
    }

    func checkStatus() async {
        guard !isChecking else { return }
        phase = .checking(cachedStatus == nil ? "Checking local model status..." : "Retrying local model status...")
        feedback = nil
        do {
            let status = try await statusReader.getLocalModelStatus(repoPath: repoPath, request: statusRequest())
            snapshot = status
            cachedStatus = status.cachedStatus
            phase = .idle
        } catch {
            phase = await .failed(localModelError(
                for: error,
                message: "Local model status could not be checked.",
                fallbackRecovery: "Retry status check"
            ))
        }
    }

    func openInstallHelp() {
        feedback = nil
        do {
            try installHelpOpener.openLocalModelInstallHelp()
            feedback = .success("Install help opened. Return here and run Retry status check.")
        } catch {
            feedback = .failed(LocalModelStatusError(
                message: "Install help could not be opened.",
                recovery: "Retry or use diagnostics.",
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
                    message: "Model location could not be opened.",
                    recovery: "Retry status check or open install help.",
                    detail: location.unavailableReason ?? "The folder is not available."
                ))
                return
            }
            try folderOpener.openLocalModelFolder(location)
            feedback = .success("Model location opened.")
        } catch {
            feedback = await .failed(localModelError(
                for: error,
                message: "Model location could not be opened.",
                fallbackRecovery: "Retry status check"
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
        let summary = snapshot?.diagnosticsSummary ?? "Local model status has not been checked yet."
        do {
            try diagnosticsCopier.copyLocalModelDiagnostics(summary)
            feedback = .success("Diagnostics summary copied.")
        } catch {
            feedback = .failed(LocalModelStatusError(
                message: "Diagnostics summary could not be copied.",
                recovery: "Retry copy.",
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
        message: String,
        fallbackRecovery: String
    ) async -> LocalModelStatusError {
        if let coreError = error as? CoreError {
            let mapping = await errorMapper.mapCoreError(coreError)
            return LocalModelStatusError(
                message: message,
                recovery: mapping.suggestedAction.isEmpty ? fallbackRecovery : mapping.suggestedAction,
                detail: mapping.userMessage
            )
        }
        return LocalModelStatusError(message: message, recovery: fallbackRecovery, detail: error.localizedDescription)
    }

    private static func statusDetail(for availability: LocalModelAvailabilityState) -> String {
        switch availability {
        case .unknown: "Local model status has not been checked yet."
        case .ready: "Local model runtime is available."
        case .notInstalled: "Local model is not installed."
        case .pathUnreadable: "Local model path cannot be read."
        case .versionIncompatible: "Local model version is not compatible."
        case .checking: "Checking local model status..."
        case .verifying: "Verifying model manifest..."
        case .loading: "Loading model runtime..."
        case .corrupted: "Model files are corrupted."
        case .runtimeFailed: "Runtime failed to start."
        case .error: "Local model status is not available yet."
        }
    }
}
